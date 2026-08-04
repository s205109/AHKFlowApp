using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class HotstringsMobileFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    private static readonly BrowserNewContextOptions TabletViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 768, Height = 1024 },
    };

    private sealed class OverflowMetrics
    {
        public int BodyOverflow { get; init; }

        public int DocumentOverflow { get; init; }
    }

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task TabletViewport_DoesNotCreatePageHorizontalOverflow()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(TabletViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");

        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px.");
    }

    [Fact]
    public async Task AddFab_OnPhoneViewport_OpensHotstringDialog()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        Task<IResponse> profilesLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/profiles", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);
        Task<IResponse> categoriesLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/categories", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");
        await Task.WhenAll(profilesLoaded, categoriesLoaded);

        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]");
    }

    [Fact]
    public async Task DesktopCreate_ThenPhoneViewport_ShowsTheNewRowInTheMobileBranch()
    {
        // No viewport option means the default 1280x720, which is wider than the 959.95px
        // breakpoint in Pages/Hotstrings.razor.css. So the page opens on the desktop branch.
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("tr.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "btwx");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", "by the way");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");

        // Resizing fetches nothing. It only changes which branch the CSS shows. So whatever the
        // mobile list holds now is exactly what the desktop mutation left behind.
        await page.SetViewportSizeAsync(375, 812);

        await page.Locator(".mobile-branch tr.mobile-row", new() { HasTextString = "btwx" })
            .WaitForAsync();
    }

}
