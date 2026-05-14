using AHKFlowApp.UI.Blazor.Components.Home;
using Bunit;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages.Home;

public sealed class HeroSectionTests : BunitContext, IAsyncLifetime
{
    public HeroSectionTests()
    {
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Renders_eyebrow_title_and_subtitle()
    {
        IRenderedComponent<HeroSection> cut = Render<HeroSection>();

        cut.Markup.Should().Contain("AUTOHOTKEY HOTSTRING MANAGER &amp; CLI");
        cut.Markup.Should().Contain("Welcome to AHK");
        cut.Markup.Should().Contain("<em>flow</em>");
        cut.Markup.Should().Contain("Manage your AutoHotkey hotstrings and hotkeys");
        cut.Markup.Should().Contain(".ahk");
    }
}
