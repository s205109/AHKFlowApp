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
        IDownloadsApiClient? downloads = null,
        IAuthTokenProvider? auth = null,
        BinaryStdout? binaryStdout = null,
        WorkingDirectory? workingDirectory = null)
    {
        ServiceCollection services = new();
        services.AddSingleton(hotstrings);
        services.AddSingleton(profiles);
        if (downloads is not null) services.AddSingleton(downloads);
        services.AddSingleton(auth ?? new StubAuthTokenProvider("test-token"));
        services.AddSingleton(binaryStdout ?? new BinaryStdout(() => new MemoryStream()));
        services.AddSingleton(workingDirectory ?? new WorkingDirectory(() => Path.GetTempPath()));
        return services.BuildServiceProvider();
    }

    public static IServiceProvider WithFactory(
        WebApplicationFactory<Program> factory,
        string? token = "test-token",
        RequestCounter? counter = null,
        Stream? stdoutSink = null,
        string? baseDirectory = null,
        TestIdentity? identity = null)
    {
        ServiceCollection services = new();
        services.AddSingleton<IAuthTokenProvider>(new StubAuthTokenProvider(token));
        services.AddTransient<BearerTokenHandler>();

        void Configure(IHttpClientBuilder builder)
        {
            builder
                .ConfigurePrimaryHttpMessageHandler(() => factory.Server.CreateHandler())
                .AddHttpMessageHandler<BearerTokenHandler>();
            if (identity is not null) builder.AddHttpMessageHandler(() => new TestIdentityHandler(identity));
            if (counter is not null) builder.AddHttpMessageHandler(() => new CountingHandler(counter));
        }

        Configure(services.AddHttpClient<IHotstringsApiClient, HotstringsApiClient>(c =>
            c.BaseAddress = new Uri("http://localhost")));
        Configure(services.AddHttpClient<IProfilesApiClient, ProfilesApiClient>(c =>
            c.BaseAddress = new Uri("http://localhost")));
        Configure(services.AddHttpClient<IDownloadsApiClient, DownloadsApiClient>(c =>
            c.BaseAddress = new Uri("http://localhost")));

        services.AddSingleton(new BinaryStdout(stdoutSink is null ? () => new MemoryStream() : () => stdoutSink));
        services.AddSingleton(new WorkingDirectory(() => baseDirectory ?? Path.GetTempPath()));

        return services.BuildServiceProvider();
    }
}
