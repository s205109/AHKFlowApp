using System.Diagnostics;
using System.Net;
using AHKFlowApp.UI.Blazor.Startup;
using FluentAssertions;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

public sealed class DevConfigTests
{
    private static HttpClient Client(HttpMessageHandler handler) =>
        new(handler) { BaseAddress = new Uri("http://localhost/") };

    /// <summary>
    /// Stops a regression from hanging the suite instead of failing it. No test measures the
    /// give-up against this number, and none comes near it: the fake-clock test finishes in a few
    /// milliseconds, and the system-clock test in about 300. It is a guard, not a budget.
    /// </summary>
    private static readonly TimeSpan HangGuard = TimeSpan.FromSeconds(30);

    /// <summary>Small enough to keep the system-clock test quick, large enough to be a real wait.</summary>
    private static readonly TimeSpan PerFileTimeout = TimeSpan.FromMilliseconds(150);

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
        //
        // A fake clock does the waiting. An earlier version asserted the call finished inside five
        // seconds of real time against a 300 ms budget. That measured thread pool availability, not
        // this code: blocking 64 pool threads drove the same call to 2044 ms with nothing changed.
        var builder = new ConfigurationBuilder();
        var clock = new FakeTimeProvider();
        using var handler = new NeverCompletingHandler(clock, PerFileTimeout);
        using HttpClient http = Client(handler);

        await builder.AddCacheBustedDevConfigAsync(http, PerFileTimeout, clock).WaitAsync(HangGuard);

        builder.Sources.Should().BeEmpty();
    }

    [Fact]
    public async Task AddCacheBustedDevConfigAsync_WithNoClockGiven_StillGivesUpOnTheSystemClock()
    {
        // The test above proves the give-up honours whatever clock it is handed. It cannot prove the
        // app gets a working one, because it never uses the default. This test does: no provider, so
        // the real timer runs. It asserts no duration — only that the call returns and adds nothing.
        // Real time here is about 300 ms, one PerFileTimeout per file.
        var builder = new ConfigurationBuilder();
        using var handler = new NeverCompletingHandler();
        using HttpClient http = Client(handler);

        Task act = builder.AddCacheBustedDevConfigAsync(http, PerFileTimeout);

        await act.WaitAsync(HangGuard);
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

    /// <summary>
    /// Accepts the request and never answers — only the caller's token ends it.
    /// </summary>
    /// <remarks>
    /// Given a fake clock, the handler moves it past one file's budget as the request arrives. The
    /// give-up timer is already armed by then, so the token is cancelled before <c>Task.Delay</c>
    /// runs, and the delay returns cancelled without ever waiting.
    /// <para>
    /// The clock is moved here rather than from the test body on purpose. A test that waits for
    /// each request, advances, and waits again needs a thread pool thread at every await. Measured
    /// on 2026-08-27 with 64 blocked pool threads, that version took 31.6 to 33.7 seconds. Doing it
    /// inside the handler keeps the whole give-up synchronous, and the same load gave 0 to 1 ms.
    /// </para>
    /// </remarks>
    private sealed class NeverCompletingHandler(FakeTimeProvider? clock = null, TimeSpan advanceBy = default)
        : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            clock?.Advance(advanceBy);
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
