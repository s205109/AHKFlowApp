using AHKFlowApp.Application.Behaviors;
using AHKFlowApp.Application.Services;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(typeof(DependencyInjection).Assembly);
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
        });

        services.AddValidatorsFromAssembly(typeof(DependencyInjection).Assembly);

        services.AddSingleton<HeaderTokenRenderer>();
        services.AddSingleton<AhkScriptGenerator>();

        return services;
    }
}
