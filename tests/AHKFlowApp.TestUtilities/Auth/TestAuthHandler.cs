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
    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        string oid = Request.Headers["X-Test-Oid"].FirstOrDefault() ?? defaults.DefaultOid.ToString();
        string email = Request.Headers["X-Test-Email"].FirstOrDefault() ?? defaults.DefaultEmail;

        List<Claim> claims =
        [
            new("oid", oid),
            new("preferred_username", email),
            new(ClaimTypes.Name, defaults.DefaultName)
        ];

        if (defaults.DefaultScope is not null)
            claims.Add(new Claim("scp", defaults.DefaultScope));

        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, Scheme.Name);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
