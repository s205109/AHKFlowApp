using Microsoft.OpenApi;

namespace AHKFlowApp.API.Extensions;

internal static class ApiExtensions
{
    internal static IServiceCollection AddConfiguredCors(
        this IServiceCollection services, string[] allowedOrigins, string policyName)
    {
        return services.AddCors(options =>
            options.AddPolicy(policyName, policy =>
            {
                if (allowedOrigins is { Length: > 0 })
                {
                    policy.WithOrigins(allowedOrigins)
                          .AllowAnyMethod()
                          .AllowAnyHeader()
                          .AllowCredentials();
                }
            }));
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
        });
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
}
