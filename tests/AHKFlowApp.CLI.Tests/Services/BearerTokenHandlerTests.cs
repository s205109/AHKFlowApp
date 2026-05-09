using System.Net;
using AHKFlowApp.CLI.Services;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Services;

public sealed class BearerTokenHandlerTests
{
    [Fact]
    public async Task SendAsync_AttachesBearerToken()
    {
        IAuthTokenProvider tokenProvider = Substitute.For<IAuthTokenProvider>();
        tokenProvider.GetTokenAsync(Arg.Any<CancellationToken>()).Returns("test-token-123");

        HttpRequestMessage capturedRequest = null!;
        var inner = new CapturingHandler(req => capturedRequest = req);

        var handler = new BearerTokenHandler(tokenProvider) { InnerHandler = inner };
        var client = new HttpClient(handler);

        await client.GetAsync("https://example.test/foo");

        capturedRequest.Headers.Authorization.Should().NotBeNull();
        capturedRequest.Headers.Authorization!.Scheme.Should().Be("Bearer");
        capturedRequest.Headers.Authorization.Parameter.Should().Be("test-token-123");
    }

    private sealed class CapturingHandler(Action<HttpRequestMessage> capture) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken ct)
        {
            capture(request);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK));
        }
    }
}
