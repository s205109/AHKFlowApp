using AHKFlowApp.UI.Blazor.Startup;
using AngleSharp.Dom;
using Bunit;
using Bunit.TestDoubles;
using FluentAssertions;
using Microsoft.AspNetCore.Components;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class StartupErrorTests : BunitContext
{
    public StartupErrorTests()
    {
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void MissingFrontendConfig_ShowsExampleAndSetupRemediation()
    {
        IRenderedComponent<StartupError> cut = Render<StartupError>(ps => ps
            .Add(p => p.Reason, StartupErrorReason.MissingFrontendConfig));

        cut.Markup.Should().Contain("appsettings.Development.json.example");
        cut.Markup.Should().Contain("setup-dev-entra.ps1");
    }

    [Fact]
    public void PlaceholderConfig_ShowsSetupScriptGuidance()
    {
        IRenderedComponent<StartupError> cut = Render<StartupError>(ps => ps
            .Add(p => p.Reason, StartupErrorReason.PlaceholderConfig));

        cut.Markup.Should().Contain("setup-dev-entra.ps1");
    }

    [Fact]
    public void BackendUnreachable_ShowsCorsRemediation()
    {
        IRenderedComponent<StartupError> cut = Render<StartupError>(ps => ps
            .Add(p => p.Reason, StartupErrorReason.BackendUnreachable));

        cut.Markup.Should().Contain("Can't reach the API");
        cut.Markup.Should().Contain("Cors:AllowedOrigins");
    }

    [Fact]
    public void Unexpected_ShowsGenericMessage()
    {
        IRenderedComponent<StartupError> cut = Render<StartupError>(ps => ps
            .Add(p => p.Reason, StartupErrorReason.Unexpected));

        cut.Markup.Should().Contain("Something went wrong");
    }

    [Fact]
    public void WhenOnRetryProvided_RendersRetryButtonAndInvokesCallback()
    {
        bool retried = false;

        IRenderedComponent<StartupError> cut = Render<StartupError>(ps => ps
            .Add(p => p.Reason, StartupErrorReason.BackendUnreachable)
            .Add(p => p.OnRetry, () => retried = true));

        cut.Markup.Should().Contain("Retry");
        cut.Find("button").Click();

        retried.Should().BeTrue();
    }

    [Fact]
    public void WhenNoOnRetry_ReloadButtonForcesFullReload()
    {
        IRenderedComponent<StartupError> cut = Render<StartupError>(ps => ps
            .Add(p => p.Reason, StartupErrorReason.MissingFrontendConfig));

        // A real <button> driving a forceLoad navigation — not an <a href="."> that Blazor
        // would intercept and route client-side without re-reading config.
        cut.Markup.Should().NotContain("<a ");
        IElement reload = cut.Find("button");
        reload.TextContent.Should().Contain("Reload");

        reload.Click();

        var nav = (BunitNavigationManager)Services.GetRequiredService<NavigationManager>();
        nav.History.Should().NotBeEmpty();
        nav.History.Last().Options.ForceLoad.Should().BeTrue();
    }
}
