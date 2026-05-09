using AHKFlowApp.API;
using AHKFlowApp.CLI.Services;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.CLI.Tests.Infrastructure;

internal static class CliTestHost
{
    public static IServiceProvider WithFakes(
        IHotstringsApiClient hotstrings,
        IProfilesApiClient profiles,
        IAuthTokenProvider? auth = null)
    {
        ServiceCollection services = new();
        services.AddSingleton(hotstrings);
        services.AddSingleton(profiles);
        services.AddSingleton(auth ?? new StubAuthTokenProvider("test-token"));
        return services.BuildServiceProvider();
    }

    public static IServiceProvider WithFactory(
        WebApplicationFactory<Program> factory,
        string? token = "test-token",
        RequestCounter? counter = null)
    {
        ServiceCollection services = new();
        services.AddSingleton<IAuthTokenProvider>(new StubAuthTokenProvider(token));
        services.AddTransient<BearerTokenHandler>();

        IHttpClientBuilder hsBuilder = services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();
        if (counter is not null) hsBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));

        IHttpClientBuilder pBuilder = services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
                c.BaseAddress = new Uri("http://localhost"))
            .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
            .AddHttpMessageHandler<BearerTokenHandler>();
        if (counter is not null) pBuilder.AddHttpMessageHandler(() => new CountingHandler(counter));

        return services.BuildServiceProvider();
    }
}
