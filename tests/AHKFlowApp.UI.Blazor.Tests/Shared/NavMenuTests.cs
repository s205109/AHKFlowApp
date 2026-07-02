using AHKFlowApp.UI.Blazor.Layout;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Shared;

public sealed class NavMenuTests : BunitContext
{
    public NavMenuTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    [Fact]
    public void NavMenu_RendersChangelogLinkAtBottom()
    {
        IRenderedComponent<NavMenu> cut = Render<NavMenu>();

        cut.Markup.Should().Contain("href=\"changelog\"");
        cut.Markup.Should().Contain("Changelog");
        cut.Markup.IndexOf("Settings", StringComparison.Ordinal).Should().BeLessThan(
            cut.Markup.IndexOf("Changelog", StringComparison.Ordinal));
    }
}
