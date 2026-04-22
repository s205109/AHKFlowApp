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
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
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

    string? appInsightsConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
    ConfigureObservability(builder, appInsightsConnectionString);

    // Start SQL Server in Docker if requested (for "https + Docker SQL" launch profile)
    if (builder.Environment.IsDevelopment() &&
        string.Equals(Environment.GetEnvironmentVariable("AHKFLOW_START_DOCKER_SQL"), "true", StringComparison.OrdinalIgnoreCase))
    {
        DevDockerSqlServer.EnsureStarted(builder.Environment.ContentRootPath);
    }

    const string corsPolicyName = "AllowConfiguredOrigins";
    string[] allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
    ConfigureServices(builder, allowedOrigins, corsPolicyName);

    WebApplication app = builder.Build();

    if (app.Environment.IsDevelopment())
    {
        await ApplyDevelopmentMigrationsAsync(app);
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
        app.UseRootRedirect("/swagger");
    }
    else
    {
        app.UseRootRedirect("/health");
    }

    if (allowedOrigins.Length > 0)
    {
        app.UseCors(corsPolicyName);
    }

    app.UseAuthentication();
    app.UseAuthorization();
    app.MapControllers();

    // Plain-text infrastructure endpoint (for load balancers, k8s probes)
    app.MapHealthChecks("/health");

    // Only when this assembly is the process entry point — skips WebApplicationFactory-hosted tests
    if (app.Environment.IsDevelopment() &&
        Assembly.GetEntryAssembly()?.GetName().Name == "AHKFlowApp.API")
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

static void ConfigureObservability(WebApplicationBuilder builder, string? appInsightsConnectionString)
{
    if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
    {
        builder.Services.AddApplicationInsightsTelemetry(options =>
            options.ConnectionString = appInsightsConnectionString);
    }

    builder.Services.AddSerilog((services, lc) =>
    {
        lc.ReadFrom.Configuration(builder.Configuration)
          .ReadFrom.Services(services)
          .Enrich.FromLogContext()
          .Enrich.WithProperty("Application", "AHKFlowApp.API");

        if (!string.IsNullOrWhiteSpace(appInsightsConnectionString))
        {
            TelemetryConfiguration telemetryConfig = services.GetRequiredService<TelemetryConfiguration>();
            lc.WriteTo.ApplicationInsights(telemetryConfig, TelemetryConverter.Traces);
        }
    });
}

static void ConfigureServices(WebApplicationBuilder builder, string[] allowedOrigins, string corsPolicyName)
{
    builder.Services.AddProblemDetails(options =>
        options.CustomizeProblemDetails = ctx =>
            ctx.ProblemDetails.Extensions["traceId"] = ctx.HttpContext.TraceIdentifier);

    builder.Services.AddControllers()
        .ConfigureApiBehaviorOptions(options =>
            options.InvalidModelStateResponseFactory = CreateValidationProblemResponse);

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

    builder.Services.AddConfiguredCors(allowedOrigins, corsPolicyName);
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"));
    builder.Services.AddAuthorization();
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<ICurrentUser, HttpContextCurrentUser>();
}

static IActionResult CreateValidationProblemResponse(ActionContext ctx)
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
}

static async Task ApplyDevelopmentMigrationsAsync(WebApplication app)
{
    await using AsyncServiceScope scope = app.Services.CreateAsyncScope();
    AppDbContext dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    ILogger<Program> logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();

    try
    {
        logger.LogInformation("Applying database migrations...");
        await dbContext.Database.MigrateAsync();
        logger.LogInformation("Database migrations applied successfully.");
    }
    catch (SqlException ex) when (ex.Number == 1801)
    {
        logger.LogInformation("Database already exists; skipping migration apply.");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error applying database migrations.");
        throw;
    }
}
