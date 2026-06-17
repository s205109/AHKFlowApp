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

    /// <summary>
    /// Fetches the dev appsettings cache-busted and adds them to <paramref name="builder"/> (later
    /// providers win, so these override any cached copies). A missing optional file is skipped.
    /// </summary>
    public static async Task AddCacheBustedDevConfigAsync(
        this IConfigurationBuilder builder, HttpClient http, CancellationToken ct = default)
    {
        foreach (string file in Files)
        {
            try
            {
                byte[] json = await http.GetByteArrayAsync($"{file}?reloadcheck={Guid.NewGuid():N}", ct);
                builder.AddJsonStream(new MemoryStream(json));
            }
            catch (HttpRequestException)
            {
                // File may legitimately be absent (e.g. appsettings.Development.json not created yet) — skip.
            }
        }
    }
}
