using AHKFlowApp.API;
using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Middleware;
using AHKFlowApp.Application;
using AHKFlowApp.Infrastructure;
using AHKFlowApp.Infrastructure.Persistence;
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

    // Stage 2: Full logger configured from appsettings.json, with DI integration
    builder.Services.AddSerilog((services, lc) => lc
        .ReadFrom.Configuration(builder.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .Enrich.WithProperty("Application", "AHKFlowApp.API"));

    // Start SQL Server in Docker if requested (for "https + Docker SQL" launch profile)
    if (builder.Environment.IsDevelopment() &&
        string.Equals(Environment.GetEnvironmentVariable("AHKFLOW_START_DOCKER_SQL"), "true", StringComparison.OrdinalIgnoreCase))
    {
        DevDockerSqlServer.EnsureStarted(builder.Environment.ContentRootPath);
    }

    builder.Services.AddControllers();
    builder.Services.AddSingleton(TimeProvider.System);
    builder.Services.AddSwaggerDocs();
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
        try
        {
            await dbContext.Database.MigrateAsync();
        }
        catch (SqlException ex) when (ex.Number == 1801)
        {
            // Database already exists (persisted Docker volume from a previous run) — migrations already applied
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

    app.UseSwaggerDocs();
    app.UseHttpsRedirection();

    if (allowedOrigins.Length > 0)
    {
        app.UseCors(corsPolicyName);
    }

    // Redirect root to Swagger UI (after HTTPS redirect so the redirect is served over HTTPS)
    app.Use(async (context, next) =>
    {
        if (context.Request.Path == "/")
        {
            context.Response.Redirect("/swagger");
            return;
        }
        await next(context);
    });

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
