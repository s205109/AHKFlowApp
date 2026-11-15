using AHKFlowApp.TestUtilities.Auth;

namespace AHKFlowApp.CLI.Tests.Infrastructure;

// Signs one request in as the given user. TestAuthHandler on the API host reads these
// headers per request, so tests that share the host never share a user.
internal sealed class TestIdentityHandler(TestUserBuilder user) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        user.ApplyTo(request.Headers);
        return base.SendAsync(request, cancellationToken);
    }
}
