using System.Net;
using System.Text;
using AHKFlowApp.UI.Blazor.Startup;
using Bunit;
using Bunit.TestDoubles;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class StartupErrorRootTests : BunitContext
{
    // appsettings.json ships with empty AzureAd values — valid config only emerges once
    // appsettings.Development.json supplies the tenant/client IDs.
    private const string BaseJson =
        """{"ApiHttpClient":{"BaseAddress":"http://localhost:5600"},"AzureAd":{"Instance":"https://login.microsoftonline.com/","TenantId":"","ClientId":"","ValidateAuthority":true}}""";

    private const string ValidDevJson =
        """{"AzureAd":{"TenantId":"tenant-123","ClientId":"client-456"}}""";

    public StartupErrorRootTests()
    {
        JSInterop.Mode = JSRuntimeMode.Loose;
        Services.AddSingleton(new StartupErrorState(StartupErrorReason.MissingFrontendConfig));
    }

    [Fact]
    public void ShowsErrorMessageWhileConfigInvalid()
    {
        UseConfigHandler(devAvailable: false);

        IRenderedComponent<StartupErrorRoot> cut = Render<StartupErrorRoot>(ps => ps
            .Add(p => p.PollInterval, TimeSpan.FromMilliseconds(10))
            .Add(p => p.ReloadDelay, TimeSpan.Zero)
            .Add(p => p.MaxAttempts, 2));

        cut.Markup.Should().Contain("Frontend configuration is missing");
    }

    [Fact]
    public async Task WhenConfigBecomesValid_ForcesFullReload()
    {
        // Dev config is missing for the first poll, then appears — simulating the user
        // restoring appsettings.Development.json while the error screen is shown.
        UseConfigHandler(devAvailable: false, devAvailableFromCall: 2);

        Render<StartupErrorRoot>(ps => ps
            .Add(p => p.PollInterval, TimeSpan.FromMilliseconds(10))
            .Add(p => p.ReloadDelay, TimeSpan.Zero)
            .Add(p => p.MaxAttempts, 50));

        var nav = (BunitNavigationManager)Services.GetRequiredService<NavigationManager>();
        DateTime deadline = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < deadline && !nav.History.Any(h => h.Options.ForceLoad))
        {
            await Task.Delay(20);
        }

        nav.History.Should().Contain(h => h.Options.ForceLoad);
    }

    private void UseConfigHandler(bool devAvailable, int devAvailableFromCall = 1)
    {
        int devCalls = 0;
        var handler = new StubHandler(request =>
        {
            string path = request.RequestUri!.AbsolutePath;

            if (path.EndsWith("appsettings.Development.json", StringComparison.Ordinal))
            {
                devCalls++;
                bool available = devAvailable || devCalls >= devAvailableFromCall;
                return available
                    ? Json(ValidDevJson)
                    : new HttpResponseMessage(HttpStatusCode.NotFound);
            }

            return Json(BaseJson);
        });

        Services.AddScoped(_ => new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });
    }

    private static HttpResponseMessage Json(string content) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(content, Encoding.UTF8, "application/json")
    };

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(responder(request));
    }
}
