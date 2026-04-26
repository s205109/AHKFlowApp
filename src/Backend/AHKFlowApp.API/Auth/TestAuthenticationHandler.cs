using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace AHKFlowApp.API.Auth;

internal sealed class TestAuthenticationHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "TestAuth";

    private const string SyntheticOid = "11111111-1111-1111-1111-111111111111";
    private const string SyntheticEmail = "local@homelab.invalid";
    private const string SyntheticName = "Local User";
    private const string Scope = "access_as_user";
    // [RequiredScope] checks the long-form URI claim; scp short-form included for forward compatibility
    private const string ScopeClaimUri = "http://schemas.microsoft.com/identity/claims/scope";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        Claim[] claims =
        [
            new("oid", SyntheticOid),
            new("preferred_username", SyntheticEmail),
            new(ClaimTypes.Name, SyntheticName),
            new("scp", Scope),
            new(ScopeClaimUri, Scope),
        ];

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
