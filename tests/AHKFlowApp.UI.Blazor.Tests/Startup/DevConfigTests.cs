using System.Diagnostics;
using System.Net;
using AHKFlowApp.UI.Blazor.Startup;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class DevConfigTests
{
    private static HttpClient Client(HttpMessageHandler handler) =>
        new(handler) { BaseAddress = new Uri("http://localhost/") };

    [Fact]
    public async Task AddCacheBustedDevConfigAsync_WhenFetchTimesOut_DoesNotThrow()
    {
        // Regression: HttpClient reports its timeout as TaskCanceledException, which was not caught.
        // This runs before RunAsync, so an escaping exception leaves the Blazor boot indicator frozen
        // at ~99% forever with nothing on screen — the app never mounts to report anything.
        var builder = new ConfigurationBuilder();
        using HttpClient http = Client(new ThrowingHandler(new TaskCanceledException()));

        Func<Task> act = () => builder.AddCacheBustedDevConfigAsync(http);

        await act.Should().NotThrowAsync();
        builder.Sources.Should().BeEmpty();
    }

    [Fact]
    public async Task AddCacheBustedDevConfigAsync_WhenFetchNeverCompletes_GivesUpAndReturns()
    {
        // The live failure: a dev host that accepts the connection but never answers. HttpClient.Timeout
        // does not help here — WebAssembly's browser handler ignores it — so the bound has to come from
        // the cancellation token. Without it the app never mounts and the boot spinner sits at ~99%.
        var builder = new ConfigurationBuilder();
        using var handler = new NeverCompletingHandler();
        using HttpClient http = Client(handler);

        Func<Task> act = () => builder.AddCacheBustedDevConfigAsync(http, TimeSpan.FromMilliseconds(150));

        await act.Should().CompleteWithinAsync(TimeSpan.FromSeconds(5));
        builder.Sources.Should().BeEmpty();
    }

    [Fact]
    public async Task AddCacheBustedDevConfigAsync_WhenFileMissing_SkipsIt()
    {
        var builder = new ConfigurationBuilder();
        using HttpClient http = Client(new StatusHandler(HttpStatusCode.NotFound));

        await builder.AddCacheBustedDevConfigAsync(http);

        builder.Sources.Should().BeEmpty();
    }

    [Fact]
    public async Task AddCacheBustedDevConfigAsync_WhenFilesLoad_AddsBothAndValuesWin()
    {
        var builder = new ConfigurationBuilder();
        builder.AddInMemoryCollection(new Dictionary<string, string?> { ["Auth:UseTestProvider"] = "false" });
        using HttpClient http = Client(new StatusHandler(HttpStatusCode.OK, """{"Auth":{"UseTestProvider":"true"}}"""));

        await builder.AddCacheBustedDevConfigAsync(http);

        // Later providers win — the fetched copy overrides whatever the cached load produced.
        builder.Build().GetValue<bool>("Auth:UseTestProvider").Should().BeTrue();
    }

    /// <summary>Accepts the request and never answers — only the caller's token ends it.</summary>
    private sealed class NeverCompletingHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            await Task.Delay(Timeout.Infinite, ct);
            throw new UnreachableException();
        }
    }

    private sealed class ThrowingHandler(Exception exception) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
            Task.FromException<HttpResponseMessage>(exception);
    }

    private sealed class StatusHandler(HttpStatusCode status, string? body = null) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var response = new HttpResponseMessage(status);
            if (body is not null)
            {
                response.Content = new StringContent(body);
            }

            // GetByteArrayAsync throws HttpRequestException on a non-success status.
            return Task.FromResult(response);
        }
    }
}
