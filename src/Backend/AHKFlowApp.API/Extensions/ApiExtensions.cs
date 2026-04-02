using Microsoft.OpenApi;

namespace AHKFlowApp.API.Extensions;

internal static class ApiExtensions
{
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

        // Redirect root to Swagger UI
        app.Use(async (context, next) =>
        {
            if (context.Request.Path == "/")
            {
                context.Response.Redirect("/swagger");
                return;
            }
            await next(context);
        });

        return app;
    }
}
