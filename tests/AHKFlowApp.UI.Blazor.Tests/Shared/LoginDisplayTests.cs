using System.Security.Claims;
using AHKFlowApp.UI.Blazor.Shared;
using Bunit;
using FluentAssertions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MudBlazor;
using MudBlazor.Services;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Shared;

public sealed class LoginDisplayTests : BunitContext, IAsyncLifetime
{
    public LoginDisplayTests()
    {
        Services.AddAuthorizationCore();
        Services.AddSingleton<IAuthorizationService, AllowAuthorizationService>();
        Services.AddMudServices();
        JSInterop.Mode = JSRuntimeMode.Loose;
    }

    Task IAsyncLifetime.InitializeAsync() => Task.CompletedTask;

    // MudBlazor's PopoverService is IAsyncDisposable-only; bUnit sync Dispose throws on
    // teardown when it's been instantiated (e.g. when MudTooltip is rendered in tests).
    async Task IAsyncLifetime.DisposeAsync() => await DisposeAsync();

    [Fact]
    public void LoginDisplay_WhenUserIsAuthenticatedInTestAuthMode_ShowsDisabledLogoutButton()
    {
        // Arrange — UseTestProvider suppresses real sign-out; logout button must be disabled
        Services.AddSingleton<IConfiguration>(BuildConfiguration(useTestAuth: true));
        Services.AddScoped<AuthenticationStateProvider>(_ => new StubAuthenticationStateProvider(isAuthenticated: true));

        // Act — MudTooltip requires MudPopoverProvider in the render tree
        Render<MudPopoverProvider>();
        IRenderedComponent<CascadingAuthenticationState> cut = Render<CascadingAuthenticationState>(parameters =>
            parameters.AddChildContent<LoginDisplay>());

        // Assert
        cut.Find("button").HasAttribute("disabled").Should().BeTrue();
    }

    [Fact]
    public void LoginDisplay_WhenUserIsAnonymous_NavigatesToAuthenticationLogin()
    {
        // Arrange
        Services.AddSingleton<IConfiguration>(BuildConfiguration(useTestAuth: false));
        Services.AddScoped<AuthenticationStateProvider>(_ => new StubAuthenticationStateProvider(isAuthenticated: false));

        // Act
        IRenderedComponent<CascadingAuthenticationState> cut = Render<CascadingAuthenticationState>(parameters =>
            parameters.AddChildContent<LoginDisplay>());

        cut.Find("button").Click();

        // Assert
        Services.GetRequiredService<NavigationManager>().Uri.Should().EndWith("/authentication/login");
    }

    [Fact]
    public void LoginDisplay_WhenUserIsAuthenticated_NavigatesToAuthenticationLogout()
    {
        // Arrange
        Services.AddSingleton<IConfiguration>(BuildConfiguration(useTestAuth: false));
        Services.AddScoped<AuthenticationStateProvider>(_ => new StubAuthenticationStateProvider(isAuthenticated: true));

        // Act
        IRenderedComponent<CascadingAuthenticationState> cut = Render<CascadingAuthenticationState>(parameters =>
            parameters.AddChildContent<LoginDisplay>());

        cut.Find("button").Click();

        // Assert
        Services.GetRequiredService<NavigationManager>().Uri.Should().EndWith("/authentication/logout");
    }

    private static IConfiguration BuildConfiguration(bool useTestAuth) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Auth:UseTestProvider"] = useTestAuth.ToString()
            })
            .Build();

    private sealed class StubAuthenticationStateProvider(bool isAuthenticated) : AuthenticationStateProvider
    {
        public override Task<AuthenticationState> GetAuthenticationStateAsync()
        {
            ClaimsIdentity identity = isAuthenticated
                ? new ClaimsIdentity([new Claim(ClaimTypes.Name, "Test User")], authenticationType: "Test")
                : new ClaimsIdentity();

            return Task.FromResult(new AuthenticationState(new ClaimsPrincipal(identity)));
        }
    }

    private sealed class AllowAuthorizationService : IAuthorizationService
    {
        public Task<AuthorizationResult> AuthorizeAsync(ClaimsPrincipal user, object? resource, IEnumerable<IAuthorizationRequirement> requirements)
            => Task.FromResult(user.Identity?.IsAuthenticated == true
                ? AuthorizationResult.Success()
                : AuthorizationResult.Failed());

        public Task<AuthorizationResult> AuthorizeAsync(ClaimsPrincipal user, object? resource, string policyName)
            => Task.FromResult(user.Identity?.IsAuthenticated == true
                ? AuthorizationResult.Success()
                : AuthorizationResult.Failed());
    }
}
