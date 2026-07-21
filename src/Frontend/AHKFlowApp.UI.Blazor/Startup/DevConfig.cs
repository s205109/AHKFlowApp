namespace AHKFlowApp.UI.Blazor.Startup;

/// <summary>
/// Loads the frontend's dev appsettings over HTTP, bypassing the browser cache. WASM fetches
/// appsettings*.json through the HTTP cache, which can serve a stale response — notably a cached
/// 404 for a previously-missing appsettings.Development.json. Re-reading cache-busted lets a freshly
/// restored/edited file be picked up on reload, and lets <see cref="StartupErrorRoot"/> detect the fix.
/// </summary>
internal static class DevConfig
{
    private static readonly string[] Files = ["appsettings.json", "appsettings.Development.json"];

    /// <summary>Two local static files; anything slower means the dev host is not healthy, and
    /// waiting longer only extends the frozen boot indicator.</summary>
    private static readonly TimeSpan DefaultPerFileTimeout = TimeSpan.FromSeconds(3);

    /// <summary>
    /// Fetches the dev appsettings cache-busted and adds them to <paramref name="builder"/> (later
    /// providers win, so these override any cached copies). A file that is missing, slow, or
    /// unreachable is skipped — the cached copy WebAssemblyHostBuilder already loaded stays in effect.
    /// </summary>
    /// <remarks>
    /// This runs before <c>RunAsync()</c>, so nothing is mounted while it is in flight and the Blazor
    /// boot indicator is frozen at ~99%. Every failure mode must therefore be caught and bounded: an
    /// escaping exception leaves that spinner up forever with no message, which reads as a hung app.
    /// </remarks>
    public static async Task AddCacheBustedDevConfigAsync(
        this IConfigurationBuilder builder,
        HttpClient http,
        TimeSpan? perFileTimeout = null,
        CancellationToken ct = default)
    {
        // The timeout rides on a token rather than HttpClient.Timeout: under WebAssembly the browser
        // HTTP handler does not enforce HttpClient.Timeout, so a stalled fetch would hang forever
        // regardless of what the client is configured with. Cancelling the token aborts the fetch.
        foreach (string file in Files)
        {
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(perFileTimeout ?? DefaultPerFileTimeout);

            try
            {
                byte[] json = await http.GetByteArrayAsync($"{file}?reloadcheck={Guid.NewGuid():N}", timeoutCts.Token);
                builder.AddJsonStream(new MemoryStream(json));
            }
            catch (HttpRequestException)
            {
                // File may legitimately be absent (e.g. appsettings.Development.json not created yet) — skip.
            }
            catch (OperationCanceledException)
            {
                // HttpClient surfaces its timeout as TaskCanceledException. A dev host that is
                // restarting or still warming up can stall these fetches; boot with the cached
                // config rather than dying before the app mounts.
            }
        }
    }
}
