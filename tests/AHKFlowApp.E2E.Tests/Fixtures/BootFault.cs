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

    /// <summary>Makes the app assembly return an empty 404, which is what reproduced the frozen boot.</summary>
    public static Task Fail404OnAppAssemblyAsync(IBrowserContext context) =>
        context.RouteAsync(AppAssemblyPattern, route => route.FulfillAsync(new RouteFulfillOptions
        {
            Status = 404,
            ContentType = "text/plain",
            Body = string.Empty,
        }));
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
