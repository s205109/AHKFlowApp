using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.JSInterop;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class LocalStorageUserPreferencesServiceTests : BunitContext
{
    public LocalStorageUserPreferencesServiceTests() => JSInterop.Mode = JSRuntimeMode.Loose;

    [Fact]
    public async Task GetAsync_WhenStorageEmpty_ReturnsDefaults()
    {
        IJSRuntime js = Services.GetService(typeof(IJSRuntime)) as IJSRuntime
            ?? throw new InvalidOperationException("JSRuntime missing");
        var service = new LocalStorageUserPreferencesService(js);

        UserPreferences result = await service.GetAsync();

        result.RowsPerPage.Should().Be(UserPreferences.Default.RowsPerPage);
        result.DarkMode.Should().Be(UserPreferences.Default.DarkMode);
    }

    [Fact]
    public async Task GetAsync_WhenStorageHasValues_ReturnsParsed()
    {
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.rowsPerPage").SetResult("50");
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.darkMode").SetResult("True");
        IJSRuntime js = Services.GetService(typeof(IJSRuntime)) as IJSRuntime
            ?? throw new InvalidOperationException("JSRuntime missing");
        var service = new LocalStorageUserPreferencesService(js);

        UserPreferences result = await service.GetAsync();

        result.RowsPerPage.Should().Be(50);
        result.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task GetAsync_WhenStorageHasGarbage_FallsBackToDefaults()
    {
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.rowsPerPage").SetResult("not-a-number");
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.darkMode").SetResult("yes-please");
        IJSRuntime js = Services.GetService(typeof(IJSRuntime)) as IJSRuntime
            ?? throw new InvalidOperationException("JSRuntime missing");
        var service = new LocalStorageUserPreferencesService(js);

        UserPreferences result = await service.GetAsync();

        result.RowsPerPage.Should().Be(UserPreferences.Default.RowsPerPage);
        result.DarkMode.Should().Be(UserPreferences.Default.DarkMode);
    }

    [Fact]
    public async Task SetAsync_WritesBothKeys()
    {
        IJSRuntime js = Services.GetService(typeof(IJSRuntime)) as IJSRuntime
            ?? throw new InvalidOperationException("JSRuntime missing");
        var service = new LocalStorageUserPreferencesService(js);

        await service.SetAsync(new UserPreferences(25, true));

        JSInterop.VerifyInvoke("localStorage.setItem", calledTimes: 2);
        JSInterop.Invocations["localStorage.setItem"]
            .Should().Contain(i => i.Arguments.Contains("ahkflow.prefs.rowsPerPage") && i.Arguments.Contains("25"));
        JSInterop.Invocations["localStorage.setItem"]
            .Should().Contain(i => i.Arguments.Contains("ahkflow.prefs.darkMode") && i.Arguments.Contains("True"));
    }
}
