using System.Security.Claims;
using System.Text.Encodings.Web;
using AHKFlowApp.UI.Blazor.Auth;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "Test";
    public static readonly Guid TestOwnerOid = Guid.Parse(TestAuthenticationProvider.TestOwnerOid);

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        Claim[] claims =
        [
            new Claim("oid", TestOwnerOid.ToString()),
            new Claim("name", "Test User"),
            new Claim("preferred_username", "test@example.com"),
            new Claim("http://schemas.microsoft.com/identity/claims/scope", "access_as_user"),
        ];
        ClaimsIdentity identity = new(claims, SchemeName);
        return Task.FromResult(AuthenticateResult.Success(
            new AuthenticationTicket(new ClaimsPrincipal(identity), SchemeName)));
    }
}
