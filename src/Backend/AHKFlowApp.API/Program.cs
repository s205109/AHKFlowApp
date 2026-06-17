using System.Diagnostics;
using System.Reflection;
using AHKFlowApp.API;
using AHKFlowApp.API.Auth;
using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Infrastructure;
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Identity.Web;
using Serilog;
using Serilog.Events;

// Stage 1: Bootstrap logger — captures startup errors before DI is ready
Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Override("Microsoft", LogEventLevel.Information)
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    Log.Information("Starting AHKFlowApp API");

    WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

    // Application Insights — only when a connection string is configured (Test/Prod)
    string? appInsightsConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
    if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
    {
        builder.Services.AddApplicationInsightsTelemetry(options =>
            options.ConnectionString = appInsightsConnectionString);
    }

    // Stage 2: Full logger configured from appsettings.json, with DI integration
    builder.Services.AddSerilog((services, lc) =>
    {
        lc.ReadFrom.Configuration(builder.Configuration)
          .ReadFrom.Services(services)
          .Enrich.FromLogContext()
          .Enrich.WithProperty("Application", "AHKFlowApp.API");

        // Route Serilog events to Application Insights when configured
        if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
        {
            TelemetryConfiguration telemetryConfig = services.GetRequiredService<TelemetryConfiguration>();
            lc.WriteTo.ApplicationInsights(telemetryConfig, TelemetryConverter.Traces);
        }
    });

    // Start SQL Server in Docker if requested (for "Docker SQL (Recommended)" launch profile)
    if (builder.Environment.IsDevelopment() &&
        string.Equals(Environment.GetEnvironmentVariable("AHKFLOW_START_DOCKER_SQL"), "true", StringComparison.OrdinalIgnoreCase))
    {
        DevDockerSqlServer.EnsureStarted(builder.Environment.ContentRootPath);

        // The compose healthcheck only proves the server is up; a database restored from the
        // persisted volume may still be recovering. Wait for it to come ONLINE and accept a
        // connection so the migration below doesn't misread the transient state and issue a
        // doomed CREATE DATABASE (error 1801) on restart.
        string? dockerSqlConnectionString = builder.Configuration.GetConnectionString("DefaultConnection");
        if (dockerSqlConnectionString is not null)
        {
            await DevDatabaseReadiness.WaitForDatabaseOnlineAsync(dockerSqlConnectionString);
        }
    }

    builder.Services.AddProblemDetails(options =>
        options.CustomizeProblemDetails = ctx =>
            ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier);

    builder.Services.AddControllers()
        .ConfigureApiBehaviorOptions(options =>
            options.InvalidModelStateResponseFactory = ctx =>
            {
                var pd = new ValidationProblemDetails(ctx.ModelState)
                {
                    Detail = "See the errors field for details.",
                    Instance = ctx.HttpContext.Request.Path,
                    Status = StatusCodes.Status422UnprocessableEntity,
                    Title = "One or more validation errors occurred."
                };
                pd.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier;
                return new UnprocessableEntityObjectResult(pd)
                {
                    ContentTypes = { "application/problem+json" }
                };
            });

    builder.Services.AddSingleton(TimeProvider.System);
    builder.Services.AddSingleton(new AppEnvironment(builder.Environment.IsDevelopment()));

    if (builder.Environment.IsDevelopment())
    {
        builder.Services.AddSwaggerDocs();
    }
    builder.Services.AddApplication();
    builder.Services.AddInfrastructure(builder.Configuration);
    builder.Services.AddHealthChecks()
        .AddDbContextCheck<AppDbContext>(
            name: "database",
            failureStatus: HealthStatus.Unhealthy);

    const string corsPolicyName = "AllowConfiguredOrigins";
    builder.Services.AddConfiguredCors(builder.Configuration, corsPolicyName);

    bool useTestAuth = builder.Configuration.GetValue<bool>("Auth:UseTestProvider");

    if (useTestAuth && !builder.Environment.IsDevelopment())
    {
        throw new InvalidOperationException(
            "Auth:UseTestProvider=true is not permitted outside the Development environment.");
    }

    if (useTestAuth)
    {
        builder.Services
            .AddAuthentication(TestAuthenticationHandler.SchemeName)
            .AddScheme<AuthenticationSchemeOptions, TestAuthenticationHandler>(
                TestAuthenticationHandler.SchemeName, _ => { });
        Log.Warning("Auth:UseTestProvider=true — synthetic auth active. Single-user / trusted-LAN only.");
    }
    else
    {
        builder.Services
            .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));
    }

    if (builder.Environment.IsDevelopment() && !useTestAuth)
    {
        builder.Configuration.WarnOnMissingDevConfig(Log.Logger);
    }

    builder.Services.AddAuthorization();
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<ICurrentUser, HttpContextCurrentUser>();

    WebApplication app = builder.Build();

    // Auto-apply migrations in Development (creates database if it doesn't exist)
    if (app.Environment.IsDevelopment())
    {
        await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
        AppDbContext dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        ILogger<Program> logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
        try
        {
            // DevDatabaseReadiness above guarantees a database restored from the persisted
            // Docker volume is ONLINE and accepting connections before this runs, so EF sees
            // it exists and applies pending migrations normally — no more transient
            // CREATE DATABASE / error 1801 to catch and swallow (which would have skipped
            // applying pending migrations).
            logger.LogInformation("Applying database migrations...");
            await dbContext.Database.MigrateAsync();
            logger.LogInformation("Database migrations applied successfully.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error applying database migrations.");
            throw;
        }
    }

    app.UseMiddleware<GlobalExceptionMiddleware>();

    if (!app.Environment.IsDevelopment())
    {
        app.UseHsts();
    }

    // Replaces per-request ASP.NET Core noise with a single structured log event per request
    app.UseSerilogRequestLogging(options =>
    {
        options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        {
            diagnosticContext.Set("RequestHost", httpContext.Request.Host.Value);
            diagnosticContext.Set("UserAgent", httpContext.Request.Headers.UserAgent.ToString());
        };
    });

    if (!app.Environment.IsDevelopment())
    {
        app.UseHttpsRedirection();
    }

    if (app.Environment.IsDevelopment())
    {
        app.UseSwaggerDocs();
    }
    app.UseRootRedirect(devTarget: "/swagger", prodTarget: "/health");
    app.UseRouting();

    // Always register CORS; the policy decides per request from live config (see AddConfiguredCors),
    // so a restored appsettings.Development.json takes effect without restarting the API.
    app.UseCors(corsPolicyName);

    app.UseDevelopmentOnlyEndpointGate();
    app.UseAuthentication();
    app.UseAuthorization();
    app.MapControllers();

    // Plain-text infrastructure endpoint (for load balancers, k8s probes)
    app.MapHealthChecks("/health");

    // Only when this assembly is the process entry point — skips WebApplicationFactory-hosted tests.
    // Suppressed whenever an IDE owns (and can close) the Swagger window itself: a debugger is
    // attached (VS via launchBrowser, VS Code F5 via serverReadyAction), or VS Code's launch.json
    // sets AHKFLOW_SUPPRESS_SWAGGER_BROWSER (covers its no-debug runs). Plain `dotnet run` leaves
    // both unset and keeps this self-open.
    if (app.Environment.IsDevelopment() &&
        Assembly.GetEntryAssembly()?.GetName().Name == "AHKFlowApp.API" &&
        !Debugger.IsAttached &&
        !string.Equals(Environment.GetEnvironmentVariable("AHKFLOW_SUPPRESS_SWAGGER_BROWSER"), "true", StringComparison.OrdinalIgnoreCase))
    {
        IHostApplicationLifetime lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();
        lifetime.ApplicationStarted.Register(() =>
        {
            string swaggerUrl = $"{app.Urls.FirstOrDefault() ?? "http://localhost:5600"}/swagger";
            try
            {
                Process.Start(new ProcessStartInfo(swaggerUrl) { UseShellExecute = true });
            }
            catch (Exception ex)
            {
                Log.Information(ex, "Unable to open Swagger UI automatically at {SwaggerUrl}", swaggerUrl);
            }
        });
    }

    Log.Information("AHKFlowApp API started successfully");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "AHKFlowApp API terminated unexpectedly");
    Environment.ExitCode = 1;
}
finally
{
    await Log.CloseAndFlushAsync();
}
