using System.Diagnostics;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Guards the failure message of FirstPageLoad.OpenAsync. A green E2E suite never runs this
// message, so without these tests it would rot unnoticed and be wrong on the day it matters.
[Collection(E2ETestCollection.Name)]
public sealed class FirstPageLoadDiagnosticsTests(StackFixture fixture) : IAsyncLifetime
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

        Func<Task> open = () => FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotkeys", "button.add-hotkey");

        TimeoutException thrown = (await open.Should().ThrowAsync<TimeoutException>()).Which;

        thrown.Message.Should().Contain("The app failed to boot");
        thrown.Message.Should().Contain("button.add-hotkey");

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

        Func<Task> open = () => FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotkeys", "button.add-hotkey");

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

        Func<Task> open = () => FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotkeys", "button.add-hotkey");
        await open.Should().ThrowAsync<TimeoutException>();

        spent.Stop();

        // Generous on purpose. Half the budget still proves the wait ended on the error screen and
        // not on the clock, and it will not turn red on a loaded runner.
        spent.Elapsed.Should().BeLessThan(TimeSpan.FromMilliseconds(FirstPageLoad.TimeoutMs / 2));
    }

    // The healthy path has to keep working, and the returned page has to be usable by the caller.
    [Fact]
    public async Task HealthyBoot_Open_ReturnsAPageShowingTheReadySelector()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotkeys", "button.add-hotkey");

        await Assertions.Expect(page.Locator("button.add-hotkey")).ToBeVisibleAsync();
        (await page.Locator("[data-test=\"boot-error\"]").CountAsync()).Should().Be(0);
    }
}
