using System.Security.Claims;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.JSInterop;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HybridUserPreferencesServiceTests : BunitContext
{
    private readonly IPreferencesApiClient _api = Substitute.For<IPreferencesApiClient>();
    private readonly StubAuthStateProvider _authProvider = new();
    private readonly LocalStorageUserPreferencesService _local;

    public HybridUserPreferencesServiceTests()
    {
        JSInterop.Mode = JSRuntimeMode.Loose;
        IJSRuntime js = Services.GetService(typeof(IJSRuntime)) as IJSRuntime
            ?? throw new InvalidOperationException("JSRuntime missing");
        _local = new LocalStorageUserPreferencesService(js);
    }

    private HybridUserPreferencesService CreateService() => new(_authProvider, _api, _local);

    [Fact]
    public async Task GetAsync_WhenUnauthenticated_ReturnsLocalStorageValues()
    {
        _authProvider.SetUnauthenticated();
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.rowsPerPage").SetResult("25");
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.darkMode").SetResult("False");
        using HybridUserPreferencesService service = CreateService();

        UserPreferences result = await service.GetAsync();

        result.RowsPerPage.Should().Be(25);
        result.DarkMode.Should().BeFalse();
        await _api.DidNotReceive().GetAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task GetAsync_WhenAuthenticatedAndServerHasData_PrefersServer()
    {
        _authProvider.SetAuthenticated();
        _api.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<UserPreferenceDto>.Ok(new UserPreferenceDto(100, true)));
        using HybridUserPreferencesService service = CreateService();

        UserPreferences result = await service.GetAsync();

        result.RowsPerPage.Should().Be(100);
        result.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task GetAsync_WhenAuthenticatedAndServerReturns404_FallsBackToLocal()
    {
        _authProvider.SetAuthenticated();
        _api.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<UserPreferenceDto>.Failure(ApiResultStatus.NotFound, null));
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.rowsPerPage").SetResult("10");
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.darkMode").SetResult("True");
        using HybridUserPreferencesService service = CreateService();

        UserPreferences result = await service.GetAsync();

        result.RowsPerPage.Should().Be(10);
        result.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task GetAsync_OnSecondCall_ServesFromCache()
    {
        _authProvider.SetAuthenticated();
        _api.GetAsync(Arg.Any<CancellationToken>())
            .Returns(ApiResult<UserPreferenceDto>.Ok(new UserPreferenceDto(50, false)));
        using HybridUserPreferencesService service = CreateService();

        await service.GetAsync();
        await service.GetAsync();

        await _api.Received(1).GetAsync(Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task SetAsync_WhenAuthenticated_WritesToLocalAndApi()
    {
        _authProvider.SetAuthenticated();
        _api.UpdateAsync(Arg.Any<UpdateUserPreferenceDto>(), Arg.Any<CancellationToken>())
            .Returns(ApiResult<UserPreferenceDto>.Ok(new UserPreferenceDto(25, true)));
        using HybridUserPreferencesService service = CreateService();

        await service.SetAsync(new UserPreferences(25, true));

        await _api.Received(1).UpdateAsync(
            Arg.Is<UpdateUserPreferenceDto>(d => d.RowsPerPage == 25 && d.DarkMode),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task SetAsync_WhenUnauthenticated_OnlyWritesLocal()
    {
        _authProvider.SetUnauthenticated();
        using HybridUserPreferencesService service = CreateService();

        await service.SetAsync(new UserPreferences(50, false));

        await _api.DidNotReceive().UpdateAsync(Arg.Any<UpdateUserPreferenceDto>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task SetAsync_WhenValueChanged_RaisesOnChange()
    {
        _authProvider.SetUnauthenticated();
        using HybridUserPreferencesService service = CreateService();
        UserPreferences? raised = null;
        service.OnChange += p => raised = p;

        await service.GetAsync();
        await service.SetAsync(new UserPreferences(50, true));

        raised.Should().NotBeNull();
        raised!.RowsPerPage.Should().Be(50);
        raised.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task SetAsync_WhenValueUnchanged_DoesNotRaiseOnChange()
    {
        _authProvider.SetUnauthenticated();
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.rowsPerPage").SetResult("10");
        JSInterop.Setup<string?>("localStorage.getItem", "ahkflow.prefs.darkMode").SetResult("False");
        using HybridUserPreferencesService service = CreateService();
        await service.GetAsync();

        int onChangeCount = 0;
        service.OnChange += _ => onChangeCount++;

        await service.SetAsync(new UserPreferences(10, false));

        onChangeCount.Should().Be(0);
    }

    [Fact]
    public void Dispose_DoesNotThrow()
    {
        HybridUserPreferencesService service = CreateService();

        Action act = service.Dispose;

        act.Should().NotThrow();
    }

    private sealed class StubAuthStateProvider : AuthenticationStateProvider
    {
        private AuthenticationState _state =
            new(new ClaimsPrincipal(new ClaimsIdentity()));

        public override Task<AuthenticationState> GetAuthenticationStateAsync() => Task.FromResult(_state);

        public void SetAuthenticated()
        {
            _state = new AuthenticationState(
                new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.Name, "test")], "test")));
            NotifyAuthenticationStateChanged(Task.FromResult(_state));
        }

        public void SetUnauthenticated()
        {
            _state = new AuthenticationState(new ClaimsPrincipal(new ClaimsIdentity()));
            NotifyAuthenticationStateChanged(Task.FromResult(_state));
        }
    }
}
