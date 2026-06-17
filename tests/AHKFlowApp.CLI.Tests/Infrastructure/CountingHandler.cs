namespace AHKFlowApp.CLI.Tests.Infrastructure;

internal sealed class RequestCounter
{
    public int TotalRequests;
    public int ProfilesRequests;
}

internal sealed class CountingHandler(RequestCounter counter) : DelegatingHandler
{
    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Interlocked.Increment(ref counter.TotalRequests);
        if (request.RequestUri?.AbsolutePath.Contains("/profiles", StringComparison.OrdinalIgnoreCase) == true)
            Interlocked.Increment(ref counter.ProfilesRequests);
        return base.SendAsync(request, cancellationToken);
    }
}
