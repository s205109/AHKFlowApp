using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using Microsoft.Playwright;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// The one wait budget for a first page load in an E2E test, and the diagnosis that runs when a
/// first page load does not arrive.
///
/// A first page load is a fresh browser context opening a page for the first time. The whole
/// Blazor WebAssembly app downloads and starts inside it, so it is the slowest wait in the suite
/// and the one most likely to be blamed for a failure it did not cause.
/// </summary>
public static class FirstPageLoad
{
    /// <summary>
    /// How long a first page load may take before the test gives up.
    ///
    /// Measured, not guessed. In CI run 34200726352 a healthy first page load reached Program.Main
    /// 0.58 seconds after the document, and made its first API call 1.8 seconds after it. So this
    /// budget is about fifteen times the healthy cost.
    ///
    /// Do not raise it to cure a flaky run. Backlog 148 found that the one run which spent this
    /// budget had a page that never booted at all, and a larger number would only have made CI
    /// spend longer reaching the same failure. A first page load that exceeds this is a broken
    /// boot, not a slow runner, and the message this class throws says which.
    /// </summary>
    public const int TimeoutMs = 30_000;

    /// <summary>
    /// The boot error screen, written by wwwroot/js/bootBlazor.js. It renders only after the one
    /// allowed retry is spent, so it is terminal: nothing can follow it, and waiting longer after
    /// it appears can never help.
    /// </summary>
    private const string BootErrorSelector = "[data-test=\"boot-error\"]";

    /// <summary>
    /// Opens a page in the given context, navigates to <paramref name="url"/>, and waits for
    /// <paramref name="readySelector"/> to become visible.
    /// </summary>
    /// <exception cref="TimeoutException">
    /// The app showed its boot error screen, or the budget ran out. The message names which, how
    /// many documents the page loaded, and every error the browser reported.
    /// </exception>
    public static async Task<IPage> OpenAsync(IBrowserContext context, string url, string readySelector)
    {
        var watch = BootWatch.Attach(context);
        IPage page = await context.NewPageAsync();
        watch.Follow(page);

        // One budget for the whole first page load, spent across both steps below. Playwright gives
        // navigation its own 30 second default, so leaving that alone would let a first page load
        // run for a full minute while the class claimed a 30 second budget.
        var spent = Stopwatch.StartNew();

        ILocator ready = page.Locator(readySelector);
        ILocator bootError = page.Locator(BootErrorSelector);

        // Both steps sit inside the try. A navigation that times out is a first page load that did
        // not arrive, and it deserves the same diagnosis as a selector that never showed.
        try
        {
            // Commit, not the default Load. bootBlazor.js can reload while the first load is still
            // settling, and waiting for Load then throws about a superseded navigation instead of
            // reaching the wait below. BootFailureFlowTests learned this the same way.
            await page.GotoAsync(url, new PageGotoOptions
            {
                WaitUntil = WaitUntilState.Commit,
                Timeout = Remaining(spent),
            });

            // Whichever arrives first ends the wait. Without the boot error in the race, a failed
            // boot would sit here for the whole budget and then report only that time had passed.
            await ready.Or(bootError).First.WaitForAsync(new LocatorWaitForOptions
            {
                Timeout = Remaining(spent),
            });
        }
        catch (TimeoutException timeout)
        {
            throw new TimeoutException(await DescribeAsync(page, readySelector, watch, spent), timeout);
        }

        if (await bootError.CountAsync() > 0)
        {
            throw new TimeoutException(await DescribeAsync(page, readySelector, watch, spent));
        }

        return page;
    }

    /// <summary>
    /// What is left of the budget, in milliseconds.
    ///
    /// Never returns zero. Playwright reads a timeout of zero as no timeout at all, so a budget
    /// that ran out during navigation would make the next wait hang forever instead of failing.
    /// </summary>
    private static float Remaining(Stopwatch spent) =>
        Math.Max(1L, TimeoutMs - spent.ElapsedMilliseconds);

    private static async Task<string> DescribeAsync(
        IPage page,
        string readySelector,
        BootWatch watch,
        Stopwatch spent)
    {
        StringBuilder report = new();

        // Both numbers, because they answer different questions. The elapsed time says what really
        // happened, and a boot that gave up early spends far less than the budget. The budget says
        // what the limit was, so a reader can tell a slow page from a page that stopped.
        report.AppendLine(
            $"The first page load never showed '{readySelector}'. "
            + $"Gave up after {spent.ElapsedMilliseconds} ms of a {TimeoutMs} ms budget.");

        // Reading the page can itself fail, and a broken diagnosis must never hide the timeout it
        // was called to explain. Both types are needed: Playwright 1.59 has no timeout exception of
        // its own, so a slow read throws System.TimeoutException, not PlaywrightException.
        try
        {
            report.AppendLine(await page.Locator(BootErrorSelector).CountAsync() > 0
                ? "The app failed to boot. The page is showing the boot error screen, so no app content was ever going to appear. A longer wait would not help."
                : "The app is not showing its boot error screen, so the boot did not report a failure.");
        }
        catch (Exception readError) when (readError is PlaywrightException or TimeoutException)
        {
            report.AppendLine($"The boot error screen could not be read: {readError.Message}");
        }

        report.AppendLine($"Documents loaded: {watch.Documents}. More than one means bootBlazor.js reloaded the page after a failed boot.");

        IReadOnlyList<string> errors = watch.Errors;
        if (errors.Count == 0)
        {
            report.AppendLine("The browser reported no console errors and no uncaught page errors.");
        }
        else
        {
            report.AppendLine("The browser reported these errors:");
            foreach (string error in errors)
            {
                report.AppendLine($"  {error}");
            }
        }

        return report.ToString();
    }
}

/// <summary>
/// Collects the three signals that tell a failed boot from a slow one: how many documents the page
/// loaded, what the console logged as an error, and what went uncaught.
/// </summary>
public sealed class BootWatch
{
    private readonly DocumentRequestCounter _documents;
    private readonly ConcurrentQueue<string> _errors = new();

    private BootWatch(DocumentRequestCounter documents) => _documents = documents;

    public int Documents => _documents.Count;

    public IReadOnlyList<string> Errors => [.. _errors];

    /// <summary>Starts counting documents. Call this before the context opens any page.</summary>
    public static BootWatch Attach(IBrowserContext context) =>
        new(DocumentRequestCounter.Attach(context));

    /// <summary>Starts collecting errors from one page. Call this before the page navigates.</summary>
    public void Follow(IPage page)
    {
        page.Console += (_, message) =>
        {
            if (message.Type == "error")
            {
                _errors.Enqueue($"console.error: {message.Text}");
            }
        };

        page.PageError += (_, error) => _errors.Enqueue($"uncaught: {error}");
    }
}
