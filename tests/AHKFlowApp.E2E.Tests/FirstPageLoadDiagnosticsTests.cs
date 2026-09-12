using System.Diagnostics;
using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Guards the failure message of FirstPageLoad.OpenAsync. A green E2E suite never runs this
// message, so without these tests it would rot unnoticed and be wrong on the day it matters.
[Collection(E2ECollectionD.Name)]
public sealed class FirstPageLoadDiagnosticsTests(StackFixtureD fixture) : IAsyncLifetime
{
    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    // The mutation this suite exists for. The app assembly 404s, so the boot fails, reloads once,
    // and ends on the error screen. The old code reported only that 30 seconds had passed.
    [Fact]
    public async Task FailedBoot_Open_ThrowsAMessageNamingTheBootFailure()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await BootFault.Fail404OnAppAssemblyAsync(ctx);

        Func<Task> open = () => FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");

        TimeoutException thrown = (await open.Should().ThrowAsync<TimeoutException>()).Which;

        thrown.Message.Should().Contain("The app failed to boot");
        thrown.Message.Should().Contain("the app shell never appeared");

        // One load, one guarded reload. The same count BootFailureFlowTests asserts exactly.
        thrown.Message.Should().Contain("Documents loaded: 2");
    }

    // The browser's own errors are the evidence backlog 148 went looking for and did not have.
    // BootWatch collects them, and nothing else in the suite reads them, so without this test the
    // collection could break and every run would still be green.
    [Fact]
    public async Task FailedBoot_Open_ReportsTheBrowsersOwnErrors()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await BootFault.Fail404OnAppAssemblyAsync(ctx);

        // Two markers the app itself would never print, one down each channel. An init script runs
        // at document start, so both land well before the boot gives up, and the reload replays
        // them.
        //
        // Neither message matches the two patterns bootBlazor.js reacts to, so an unrelated error
        // cannot change the boot outcome. SlowBoot_WithUnrelatedUncaughtError_StillRendersApp
        // proves that separately, and uses this same setTimeout shape.
        await ctx.AddInitScriptAsync(
            "console.error('E2E-CONSOLE-MARKER');"
            + "setTimeout(function () { throw new Error('E2E-UNCAUGHT-MARKER'); }, 0);");

        Func<Task> open = () => FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");

        TimeoutException thrown = (await open.Should().ThrowAsync<TimeoutException>()).Which;

        thrown.Message.Should().Contain("console.error: E2E-CONSOLE-MARKER");

        // Split from the marker on purpose. The browser prefixes an uncaught error with its own
        // type name, so asserting the whole line as one string would be brittle.
        thrown.Message.Should().Contain("uncaught: ");
        thrown.Message.Should().Contain("E2E-UNCAUGHT-MARKER");
    }

    // Failing fast matters as much as failing clearly. The boot error is terminal, so waiting the
    // rest of the budget after it appears would waste 29 seconds of every such CI run.
    [Fact]
    public async Task FailedBoot_Open_GivesUpWithoutSpendingTheWholeBudget()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await BootFault.Fail404OnAppAssemblyAsync(ctx);

        // Stopwatch, not the wall clock. It is monotonic, so a clock adjustment mid-test cannot
        // turn this assertion red or green on its own.
        var spent = Stopwatch.StartNew();

        Func<Task> open = () => FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
        TimeoutException thrown = (await open.Should().ThrowAsync<TimeoutException>()).Which;

        spent.Stop();

        // Generous on purpose. Half the budget still proves the wait ended on the error screen and
        // not on the clock, and it will not turn red on a loaded runner.
        spent.Elapsed.Should().BeLessThan(TimeSpan.FromMilliseconds(FirstPageLoad.TimeoutMs / 2));

        // The message has to report the time that really passed, not the budget it was allowed.
        // A boot that gave up in a second saying it waited thirty would send the next reader
        // hunting for a slow runner, which is the wrong trail and the one backlog 148 followed.
        Match reported = Regex.Match(thrown.Message, @"Gave up after (\d+) ms");
        reported.Success.Should().BeTrue("the message states how long it actually waited");

        int.Parse(reported.Groups[1].Value)
            .Should().BeLessThan(FirstPageLoad.TimeoutMs / 2);
    }

    // The healthy path has to keep working, and the returned page has to be usable by the caller.
    [Fact]
    public async Task HealthyBoot_Open_ReturnsAPageShowingTheApp()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");

        await Assertions.Expect(page.Locator("[data-test=\"app-shell\"]")).ToBeVisibleAsync();
        await Assertions.Expect(page.Locator("button.add-hotkey")).ToBeVisibleAsync();
        (await page.Locator("[data-test=\"boot-error\"]").CountAsync()).Should().Be(0);
    }

    // The blind spot backlog 154 found. The app can start and still be unable to run, and the old
    // diagnosis reported that as "the boot did not report a failure" — the wrong trail.
    //
    // SpaHost serves every appsettings request with Auth:UseTestProvider=true, and that flag makes
    // Program.cs skip the configuration check entirely. This route serves configuration without the
    // flag and without the Azure AD keys, so the check runs, fails, and the app boots its error
    // root instead of the app. The app shell therefore never appears.
    [Fact]
    public async Task UnusableConfiguration_Open_ThrowsAMessageNamingTheStartupErrorScreen()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        await ctx.RouteAsync("**/appsettings*.json", route => route.FulfillAsync(new RouteFulfillOptions
        {
            Status = 200,
            ContentType = "application/json",
            Body = """{"ApiHttpClient":{"BaseAddress":"/"}}""",
        }));

        Func<Task> open = () => FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");

        TimeoutException thrown = (await open.Should().ThrowAsync<TimeoutException>()).Which;

        thrown.Message.Should().Contain("The app started but could not run");
        thrown.Message.Should().Contain("MissingFrontendConfig");

        // The boot never failed, so the boot sentence must not appear. Printing both would send the
        // reader down the trail this class exists to close.
        thrown.Message.Should().NotContain("The app failed to boot");
    }

    // The evidence that actually named the second CI failure in backlog 154, and the only piece
    // that lived outside the test process until now.
    [Fact]
    public async Task FailedBoot_Open_ReportsTheLastRequestsThePageMade()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await BootFault.Fail404OnAppAssemblyAsync(ctx);

        Func<Task> open = () => FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");

        TimeoutException thrown = (await open.Should().ThrowAsync<TimeoutException>()).Which;

        thrown.Message.Should().Contain("The last requests the page made:");

        // Every boot asks for this file, and it is the request the second CI failure stopped after.
        thrown.Message.Should().Contain("blazor.webassembly.js");

        // An offset, not a wall clock. A reader needs the gap between requests, which is what says
        // "and then it stopped", and an absolute time cannot show that at a glance.
        thrown.Message.Should().MatchRegex(@"\d+ ms  http");
    }

    // A first attempt at this test fulfilled the response as fast as possible and asserted the
    // helper still saw it. That proves nothing: the helper navigates with WaitUntilState.Commit,
    // which returns when the document arrives, and the app cannot call the API until the runtime
    // has started seconds later. A registration placed anywhere before the app shell wait would
    // still have caught it, so the test passed with the bug in place.
    //
    // So the ordering is forced, not raced. The app shell is held invisible until the response has
    // completed, which makes "the response finished first" a fact rather than a hope.
    [Fact]
    public async Task AResponseThatFinishesBeforeTheAppShell_IsStillObserved()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        // Playwright's "visible" state means a non-empty bounding box and no visibility:hidden, so
        // this rule alone stops the helper's wait from finishing. Injected at document start, so it
        // is in place before MainLayout ever renders.
        await ctx.AddInitScriptAsync(
            "document.addEventListener('DOMContentLoaded', function () {"
            + "  var s = document.createElement('style');"
            + "  s.id = 'e2e-hold-shell';"
            + "  s.textContent = '[data-test=\"app-shell\"]{visibility:hidden}';"
            + "  document.head.appendChild(s);"
            + "});");

        TaskCompletionSource fulfilled = new(TaskCreationOptions.RunContinuationsAsynchronously);

        await ctx.RouteAsync("**/api/v1/profiles*", async route =>
        {
            await route.FulfillAsync(new RouteFulfillOptions
            {
                Status = 200,
                ContentType = "application/json",
                Body = "[]",
            });

            fulfilled.TrySetResult();
        });

        // Started, not awaited. The test has to act while the helper is still inside its wait.
        Task<IPage> opening = FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotkeys", "/api/v1/profiles");

        // The response has now completed. The helper cannot have returned: the shell is hidden.
        await WaitForResponseOrOpenFailureAsync(fulfilled.Task, opening);

        IPage page = ctx.Pages.Single();
        await page.EvaluateAsync("() => document.getElementById('e2e-hold-shell')?.remove()");

        // Times out if the helper registered its wait after the app shell appeared, because by then
        // the response was already gone.
        IPage opened = await opening;

        (await opened.Locator("[data-test=\"app-shell\"]").CountAsync()).Should().Be(1);
    }

    /// <summary>
    /// Waits for <paramref name="responded"/> while watching <paramref name="opening"/>, and never
    /// waits without a limit.
    /// </summary>
    /// <remarks>
    /// Whichever ends first decides. If the helper ends first, its own exception is rethrown, so a
    /// failed boot reports as the boot diagnosis rather than as a hang. If it returns without
    /// failing, the app shell was not held back and the caller's test would prove nothing.
    ///
    /// The limit is twice the budget, so the helper's own 30 second diagnosis always arrives first.
    /// The limit exists only for the case where neither side ever ends.
    /// </remarks>
    private static async Task WaitForResponseOrOpenFailureAsync(Task responded, Task<IPage> opening)
    {
        Task first;
        try
        {
            first = await Task.WhenAny(responded, opening)
                .WaitAsync(TimeSpan.FromMilliseconds(FirstPageLoad.TimeoutMs * 2));
        }
        catch (TimeoutException timeout)
        {
            throw new TimeoutException(
                "The response never completed, and FirstPageLoad.OpenAsync neither returned nor failed.",
                timeout);
        }

        if (first == opening)
        {
            await opening;
            throw new InvalidOperationException(
                "FirstPageLoad.OpenAsync returned before the response completed, so the app shell was "
                + "not held back and this test proves nothing.");
        }
    }

    // The review finding against the test above. Its wait for the response once had no limit and
    // never looked at the helper, so a boot that failed before asking for profiles left the test
    // waiting forever instead of failing. The boot is broken here on purpose, so the response never
    // comes, and the wait must end on the helper's own boot diagnosis, well inside the budget.
    [Fact]
    public async Task FailedBoot_WhileWaitingForTheResponse_SurfacesTheBootFailureInsteadOfHanging()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await BootFault.Fail404OnAppAssemblyAsync(ctx);

        TaskCompletionSource neverResponds = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var spent = Stopwatch.StartNew();

        Task<IPage> opening = FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotkeys", "/api/v1/profiles");

        Func<Task> wait = () => WaitForResponseOrOpenFailureAsync(neverResponds.Task, opening);

        TimeoutException thrown = (await wait.Should().ThrowAsync<TimeoutException>()).Which;
        spent.Stop();

        thrown.Message.Should().Contain("The app failed to boot");
        spent.Elapsed.Should().BeLessThan(TimeSpan.FromMilliseconds(FirstPageLoad.TimeoutMs / 2));
    }
}
