namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Installs the Playwright browser once per test process.
/// </summary>
/// <remarks>
/// Every stack needs the browser, and the stacks start together. Four installs writing into one
/// shared browser folder is a race, so the first caller does the work and the rest wait for it.
/// One stack calls this once, so the wait costs nothing worth saving with a lock-free fast path.
/// </remarks>
internal static class BrowserInstall
{
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static bool _installed;

    public static async Task EnsureChromiumAsync()
    {
        await Gate.WaitAsync();
        try
        {
            if (_installed)
            {
                return;
            }

            int exitCode = Microsoft.Playwright.Program.Main(["install", "chromium"]);
            if (exitCode != 0)
            {
                throw new InvalidOperationException($"Playwright browser installation failed (exit {exitCode}).");
            }

            _installed = true;
        }
        finally
        {
            Gate.Release();
        }
    }
}
