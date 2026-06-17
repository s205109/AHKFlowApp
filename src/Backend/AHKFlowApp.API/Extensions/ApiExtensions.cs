using System.Reflection;
using AHKFlowApp.API.Filters;
using Microsoft.OpenApi;
using Swashbuckle.AspNetCore.Filters;

namespace AHKFlowApp.API.Extensions;

internal static class ApiExtensions
{
    internal static IServiceCollection AddConfiguredCors(
        this IServiceCollection services, IConfiguration configuration, string policyName)
    {
        // SetIsOriginAllowed runs per request and reads Cors:AllowedOrigins live, so a restored/edited
        // appsettings.Development.json is honored via reloadOnChange without restarting the API.
        // Empty origins => predicate returns false => no CORS headers (request correctly blocked).
        return services.AddCors(options =>
            options.AddPolicy(policyName, policy =>
                policy.SetIsOriginAllowed(origin =>
                          (configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [])
                              .Contains(origin, StringComparer.OrdinalIgnoreCase))
                      .WithMethods("GET", "POST", "PUT", "DELETE")
                      .WithHeaders("Content-Type", "Authorization")
                      .AllowCredentials()));
    }

    /// <summary>
    /// Logs actionable warnings (non-fatal) when local dev config the frontend depends on is missing,
    /// so a forgotten appsettings.Development.json surfaces a clear message instead of a CORS/blank page.
    /// </summary>
    internal static void WarnOnMissingDevConfig(this IConfiguration configuration, Serilog.ILogger logger)
    {
        if (string.IsNullOrWhiteSpace(configuration["AzureAd:TenantId"]) ||
            string.IsNullOrWhiteSpace(configuration["AzureAd:ClientId"]))
        {
            logger.Warning(
                "AzureAd:TenantId/ClientId is not configured. Set it via user-secrets or run " +
                "scripts/setup-dev-entra.ps1 (see appsettings.Development.json.example). " +
                "Token validation will reject all authenticated requests until this is set.");
        }

        string[] allowedOrigins = configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
        if (allowedOrigins.Length == 0)
        {
            logger.Warning(
                "Cors:AllowedOrigins is empty — the Blazor frontend (http://localhost:5601) will be blocked " +
                "by CORS. Copy appsettings.Development.json.example to appsettings.Development.json and set it.");
        }
    }

    internal static IServiceCollection AddSwaggerDocs(this IServiceCollection services)
    {
        services.AddEndpointsApiExplorer();
        services.AddSwaggerGen(options =>
        {
            options.SwaggerDoc("v1", new OpenApiInfo
            {
                Title = "AHKFlowApp API",
                Version = "v1"
            });

            options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
            {
                Scheme = "bearer",
                BearerFormat = "JWT",
                In = ParameterLocation.Header,
                Type = SecuritySchemeType.Http
            });
            options.AddSecurityRequirement(doc => new OpenApiSecurityRequirement
            {
                {
                    new OpenApiSecuritySchemeReference("Bearer", doc),
                    []
                }
            });

            foreach (string assemblyName in new[] { "AHKFlowApp.API", "AHKFlowApp.Application" })
            {
                string xmlPath = Path.Combine(AppContext.BaseDirectory, $"{assemblyName}.xml");
                if (File.Exists(xmlPath))
                    options.IncludeXmlComments(xmlPath, includeControllerXmlComments: true);
            }

            options.ExampleFilters();
        });

        services.AddSwaggerExamplesFromAssemblies(Assembly.GetExecutingAssembly());

        return services;
    }

    internal static WebApplication UseSwaggerDocs(this WebApplication app)
    {
        app.UseSwagger();
        app.UseSwaggerUI(options =>
        {
            options.SwaggerEndpoint("/swagger/v1/swagger.json", "AHKFlowApp API v1");
            options.RoutePrefix = "swagger";
        });

        return app;
    }

    internal static WebApplication UseRootRedirect(this WebApplication app, string devTarget, string prodTarget)
    {
        string target = app.Environment.IsDevelopment() ? devTarget : prodTarget;
        app.Use(async (context, next) =>
        {
            if (context.Request.Path == "/")
            {
                context.Response.Redirect(target);
                return;
            }
            await next(context);
        });
        return app;
    }

    internal static WebApplication UseDevelopmentOnlyEndpointGate(this WebApplication app)
    {
        app.Use(async (context, next) =>
        {
            bool isDevelopmentOnly = context.GetEndpoint()?.Metadata.GetMetadata<DevelopmentOnlyAttribute>() is not null;
            if (!app.Environment.IsDevelopment() && isDevelopmentOnly)
            {
                context.Response.StatusCode = StatusCodes.Status404NotFound;
                return;
            }

            await next(context);
        });

        return app;
    }
}
