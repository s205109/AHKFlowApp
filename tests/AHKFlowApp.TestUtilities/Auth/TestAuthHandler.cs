using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace AHKFlowApp.TestUtilities.Auth;

public sealed class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder,
    TestUserBuilder defaults)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    private const string ScopeClaimUri = "http://schemas.microsoft.com/identity/claims/scope";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        bool authenticate = defaults.DefaultAuthenticate
            || (Request.Headers.TryGetValue("X-Test-Auth", out Microsoft.Extensions.Primitives.StringValues authHeader)
                && bool.TryParse(authHeader.FirstOrDefault(), out bool parsedAuthenticate)
                && parsedAuthenticate);

        if (!authenticate)
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }

        string oid = Request.Headers["X-Test-Oid"].FirstOrDefault() ?? defaults.DefaultOid.ToString();
        string email = Request.Headers["X-Test-Email"].FirstOrDefault() ?? defaults.DefaultEmail;
        string name = Request.Headers["X-Test-Name"].FirstOrDefault() ?? defaults.DefaultName;
        bool withoutScope = bool.TryParse(Request.Headers["X-Test-Without-Scope"].FirstOrDefault(), out bool parsedWithoutScope)
            && parsedWithoutScope;
        string? scope = withoutScope
            ? null
            : Request.Headers["X-Test-Scope"].FirstOrDefault() ?? defaults.DefaultScope;

        List<Claim> claims =
        [
            new("oid", oid),
            new("preferred_username", email),
            new(ClaimTypes.Name, name)
        ];

        if (!string.IsNullOrWhiteSpace(scope))
        {
            claims.Add(new Claim("scp", scope));
            claims.Add(new Claim(ScopeClaimUri, scope));
        }

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
