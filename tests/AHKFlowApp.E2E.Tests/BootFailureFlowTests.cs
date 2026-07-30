using System.Diagnostics;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Guards the boot path in wwwroot/js/bootBlazor.js. Blazor is started manually so a boot
// failure ends in a visible message instead of a loading circle frozen at 99%.
[Collection(E2ETestCollection.Name)]
public sealed class BootFailureFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private const string ReloadGuardKey = "ahkflowapp-boot-retry-reload";

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task SuccessfulBoot_RendersApp_AndClearsReloadGuard()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        // Pre-set the guard so this proves clearing, not just absence. Without the clear,
        // one recovered failure would cost the next unrelated failure its free retry.
        await ctx.AddInitScriptAsync($"sessionStorage.setItem('{ReloadGuardKey}', 'true');");

        IPage page = await ctx.NewPageAsync();
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");

        // The app renders as before: manual start changed nothing on the success path.
        await page.WaitForSelectorAsync("button.add-hotstring");

        string? guard = await page.EvaluateAsync<string?>(
            $"() => sessionStorage.getItem('{ReloadGuardKey}')");
        guard.Should().BeNull();
    }

    [Fact]
    public async Task FirstBootFailure_ReloadsThePage()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await BootFault.Fail404OnAppAssemblyAsync(ctx);
        var documents = DocumentRequestCounter.Attach(ctx);

        IPage page = await ctx.NewPageAsync();

        // Commit, not load: the boot script may reload while the first load is still settling,
        // and a superseded navigation makes the default wait throw.
        await page.GotoAsync(fixture.Spa.BaseUrl, new PageGotoOptions { WaitUntil = WaitUntilState.Commit });

        // The reload happened: the document was requested a second time. This test proves the
        // reload, nothing more. That the reload happens at most once is proven in Task 3, where
        // the error screen gives a terminal state to wait for.
        await WaitUntilAsync(() => documents.Count >= 2, "the page to reload after the first boot failure");
    }

    // Playwright's own waits are tied to a page, and the page navigates underneath these tests,
    // so poll the context-level counter instead.
    private static async Task WaitUntilAsync(Func<bool> condition, string description)
    {
        var elapsed = Stopwatch.StartNew();
        while (elapsed.Elapsed < TimeSpan.FromSeconds(60))
        {
            if (condition())
            {
                return;
            }

            await Task.Delay(100);
        }

        throw new TimeoutException($"Timed out waiting for {description}.");
    }
}
