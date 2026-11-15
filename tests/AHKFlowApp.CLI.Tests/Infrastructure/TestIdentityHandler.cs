namespace AHKFlowApp.CLI.Tests.Infrastructure;

// Signs one request in as the given identity. TestAuthHandler on the API host reads these
// headers per request, so tests that share the host never share a user.
internal sealed class TestIdentityHandler(TestIdentity identity) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        request.Headers.Add("X-Test-Auth", "true");
        request.Headers.Add("X-Test-Oid", identity.Oid.ToString());
        request.Headers.Add("X-Test-Email", identity.Email);
        if (identity.WithoutScope)
            request.Headers.Add("X-Test-Without-Scope", "true");

        return base.SendAsync(request, cancellationToken);
    }
}
