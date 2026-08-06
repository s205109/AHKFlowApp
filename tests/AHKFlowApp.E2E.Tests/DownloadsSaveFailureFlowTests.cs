using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class DownloadsSaveFailureFlowTests(StackFixture fixture) : IAsyncLifetime
{
    // Trailing "undefined;" stops Playwright from auto-invoking the assignment's completion
    // value (the arrow function itself) — EvaluateAsync calls a function-valued result.
    private const string BreakSaveBlob =
        "window.ahkFlowDownloads.saveBlob = () => { throw new Error('the browser refused the download'); }; undefined;";

    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task ProfileDownload_WhenTheSaveFails_ReportsItAndFreesTheButton()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");
        await page.EvaluateAsync(BreakSaveBlob);
        await page.ClickAsync("button.download-profile");

        await page.WaitForSelectorAsync("text=Saving the file failed.");
        await page.WaitForSelectorAsync("button.download-profile:not([disabled])");
    }

    [Fact]
    public async Task DownloadAll_WhenTheSaveFails_ReportsItAndFreesTheButton()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");
        await page.EvaluateAsync(BreakSaveBlob);
        await page.ClickAsync("button.download-all");

        await page.WaitForSelectorAsync("text=Saving the file failed.");
        await page.WaitForSelectorAsync("button.download-all:not([disabled])");
    }
}
