using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;

namespace AHKFlowApp.UI.Blazor.Auth;

public sealed class TestAuthenticationProvider : AuthenticationStateProvider
{
    public const string TestOwnerOid = "11111111-1111-1111-1111-111111111111";

    public override Task<AuthenticationState> GetAuthenticationStateAsync()
    {
        var identity = new ClaimsIdentity(
        [
            new Claim("oid", TestOwnerOid),
            new Claim("name", "Test User"),
            new Claim("preferred_username", "test@example.com"),
            new Claim("http://schemas.microsoft.com/identity/claims/scope", "access_as_user"),
        ], authenticationType: "Test");
        return Task.FromResult(new AuthenticationState(new ClaimsPrincipal(identity)));
    }
}
