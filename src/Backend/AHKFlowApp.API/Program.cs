using AHKFlowApp.API;
using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;
using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.ApplicationInsights.Extensibility;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
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

    // Start SQL Server in Docker if requested (for "https + Docker SQL" launch profile)
    if (builder.Environment.IsDevelopment() &&
        string.Equals(Environment.GetEnvironmentVariable("AHKFLOW_START_DOCKER_SQL"), "true", StringComparison.OrdinalIgnoreCase))
    {
        DevDockerSqlServer.EnsureStarted(builder.Environment.ContentRootPath);
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
    string[] allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
    builder.Services.AddConfiguredCors(allowedOrigins, corsPolicyName);

    WebApplication app = builder.Build();

    // Auto-apply migrations in Development (creates database if it doesn't exist)
    if (app.Environment.IsDevelopment())
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
            // Database already exists (persisted Docker volume from a previous run) — migrations already applied
            logger.LogInformation("Database already exists; skipping migration apply.");
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

    if (app.Environment.IsDevelopment())
    {
        app.UseSwaggerDocs();
        app.Use(async (context, next) =>
        {
            if (context.Request.Path == "/")
            {
                context.Response.Redirect("/swagger");
                return;
            }
            await next(context);
        });
    }

    app.UseHttpsRedirection();

    if (allowedOrigins.Length > 0)
    {
        app.UseCors(corsPolicyName);
    }

    app.UseAuthorization();
    app.MapControllers();

    // Plain-text infrastructure endpoint (for load balancers, k8s probes)
    app.MapHealthChecks("/health");

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
