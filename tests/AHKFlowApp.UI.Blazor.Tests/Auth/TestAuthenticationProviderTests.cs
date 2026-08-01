using AHKFlowApp.UI.Blazor.Auth;
using FluentAssertions;
using Microsoft.AspNetCore.Components.Authorization;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Auth;

public sealed class TestAuthenticationProviderTests
{
    [Fact]
    public async Task GetAuthenticationStateAsync_Always_NameIsTestUser()
    {
        var provider = new TestAuthenticationProvider();

        AuthenticationState state = await provider.GetAuthenticationStateAsync();

        state.User.Identity!.Name.Should().Be("Test User");
    }

    [Fact]
    public async Task GetAuthenticationStateAsync_Always_IsAuthenticated()
    {
        var provider = new TestAuthenticationProvider();

        AuthenticationState state = await provider.GetAuthenticationStateAsync();

        state.User.Identity!.IsAuthenticated.Should().BeTrue();
    }
}
