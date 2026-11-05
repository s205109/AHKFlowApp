using System.Text.RegularExpressions;
using Microsoft.Playwright;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Fault injection for the Blazor boot path. Routes are registered on the browser context, not on
/// one page, so the fault survives the reload that the boot script performs.
/// </summary>
public static class BootFault
{
    /// <summary>
    /// The app assembly. Publish fingerprints the file name on every build, so match the pattern
    /// instead of a fixed name. Exactly one file matches at run time: the one the boot config names.
    /// A regular expression, not a glob: a glob such as "**/_framework/AHKFlowApp.UI.Blazor.*.wasm"
    /// never matched the absolute request URL in Playwright 1.59, so the fault was never injected.
    /// </summary>
    public static readonly Regex AppAssemblyPattern =
        new(@"/_framework/AHKFlowApp\.UI\.Blazor\.[^/]+\.wasm$", RegexOptions.None, TimeSpan.FromSeconds(1));

    /// <summary>
    /// The boot grace period these tests use, in milliseconds. Production waits 10 s after a failed
    /// download before it reports the boot as failed (bootBlazor.js). Every test that injects a
    /// fault would wait that long, so each fault also sets this short wait.
    /// </summary>
    public const int ShortGraceMs = 1000;

    /// <summary>Makes the app assembly return an empty 404, which is what reproduced the frozen boot.</summary>
    public static async Task Fail404OnAppAssemblyAsync(IBrowserContext context)
    {
        await UseShortGraceAsync(context);
        await context.RouteAsync(AppAssemblyPattern, route => route.FulfillAsync(new RouteFulfillOptions
        {
            Status = 404,
            ContentType = "text/plain",
            Body = string.Empty,
        }));
    }

    /// <summary>
    /// Serves the app assembly normally, but late. Used to prove that a boot slower than the grace
    /// period still counts as a success.
    /// </summary>
    public static async Task DelayAppAssemblyAsync(IBrowserContext context, TimeSpan delay)
    {
        await UseShortGraceAsync(context);
        await context.RouteAsync(AppAssemblyPattern, async route =>
        {
            await Task.Delay(delay);
            await route.ContinueAsync();
        });
    }

    // An init script runs before every page script, on every navigation, so the value is in place
    // before bootBlazor.js reads it, and it survives the reload the boot script performs.
    private static Task UseShortGraceAsync(IBrowserContext context) =>
        context.AddInitScriptAsync($"window.__ahkflowBootFailureGraceMs = {ShortGraceMs};");
}

/// <summary>
/// Counts top-level document requests on a browser context. This is how the tests tell one page
/// load from a reload.
/// </summary>
public sealed class DocumentRequestCounter
{
    private int _count;

    public int Count => Volatile.Read(ref _count);

    public static DocumentRequestCounter Attach(IBrowserContext context)
    {
        DocumentRequestCounter counter = new();
        context.Request += (_, request) =>
        {
            if (request.ResourceType == "document")
            {
                Interlocked.Increment(ref counter._count);
            }
        };

        return counter;
    }
}
