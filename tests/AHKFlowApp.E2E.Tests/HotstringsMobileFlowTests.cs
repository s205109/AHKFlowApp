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
    public async Task CreateEditDelete_OnPhoneViewport_UsesFabAndFullScreenDialog()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");

        // Add via FAB
        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.FillAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]", "mob");
        await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "mobile by the way");
        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"mob\")");

        // Expand row, click edit, change, save
        await page.ClickAsync(".mobile-row:has-text(\"mob\")");
        await page.WaitForSelectorAsync(".mobile-row-expanded button.start-edit");
        await page.ClickAsync(".mobile-row-expanded button.start-edit");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "edited!");
        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring updated.");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"edited!\")");

        // Delete via expanded row (row stays expanded after dialog close)
        await page.WaitForSelectorAsync(".mobile-row-expanded button.delete");
        await page.ClickAsync(".mobile-row-expanded button.delete");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.Locator("[role=\"dialog\"]").GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Hotstring deleted.");
    }

}
