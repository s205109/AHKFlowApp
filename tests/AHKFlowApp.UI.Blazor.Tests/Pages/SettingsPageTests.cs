using AHKFlowApp.UI.Blazor.Pages;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Pages;

public sealed class SettingsPageTests : BunitContext, IAsyncLifetime
{
    private readonly IUserPreferencesService _prefs = Substitute.For<IUserPreferencesService>();
    private readonly IWebAssemblyHostEnvironment _env = Substitute.For<IWebAssemblyHostEnvironment>();

    public SettingsPageTests()
    {
        _env.Environment.Returns("Production");
        Services.AddSingleton(_prefs);
        Services.AddSingleton(_env);
        Services.AddSingleton<ISnackbar>(Substitute.For<ISnackbar>());
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void Page_OnLoad_RendersCurrentPreferences()
    {
        _prefs.GetAsync(Arg.Any<CancellationToken>()).Returns(new UserPreferences(50, true));

        Render<MudPopoverProvider>();
        IRenderedComponent<Settings> cut = Render<Settings>();

        cut.WaitForAssertion(() => cut.Markup.Should().Contain("Settings"));
        cut.Markup.Should().Contain("Rows per page");
        cut.Markup.Should().Contain("Default theme");
    }

    [Fact]
    public Task Page_SaveButton_CallsSetAsyncWithCurrentValues()
    {
        _prefs.GetAsync(Arg.Any<CancellationToken>()).Returns(new UserPreferences(25, false));

        Render<MudPopoverProvider>();
        IRenderedComponent<Settings> cut = Render<Settings>();
        cut.WaitForAssertion(() => cut.Find("button.save-settings"));

        cut.Find("button.save-settings").Click();

        cut.WaitForAssertion(() => _prefs.Received(1).SetAsync(
            Arg.Is<UserPreferences>(p => p.RowsPerPage == 25 && !p.DarkMode),
            Arg.Any<CancellationToken>()));
        return Task.CompletedTask;
    }

    [Fact]
    public void Page_HasSaveButton()
    {
        _prefs.GetAsync(Arg.Any<CancellationToken>()).Returns(UserPreferences.Default);

        Render<MudPopoverProvider>();
        IRenderedComponent<Settings> cut = Render<Settings>();

        cut.WaitForAssertion(() => cut.Find("button.save-settings").Should().NotBeNull());
    }
}
