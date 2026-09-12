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
}
