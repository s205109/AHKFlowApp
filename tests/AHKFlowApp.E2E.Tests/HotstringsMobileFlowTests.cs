using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class HotstringsMobileFlowTests(StackFixture fixture) : IClassFixture<StackFixture>
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

    [Fact]
    public async Task BulkDelete_OnPhoneViewport_UsesSelectMode()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");

        // Create two rows via FAB
        foreach (string trig in new[] { "bk1", "bk2" })
        {
            await page.ClickAsync("button.add-hotstring-fab");
            await page.WaitForSelectorAsync(".hotstring-edit-dialog");
            await page.FillAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]", trig);
            await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "x");
            await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");
            await page.WaitForSelectorAsync($".mobile-row:has-text(\"{trig}\")");
        }

        // Enter select mode + select both
        await page.ClickAsync("button.toggle-select-mode");
        await page.WaitForSelectorAsync("input.row-checkbox");
        foreach (string trig in new[] { "bk1", "bk2" })
            await page.Locator($"xpath=//tr[contains(@class,'mobile-row')][.//code[normalize-space(.)='{trig}']]//input[contains(@class,'row-checkbox')]").CheckAsync();

        await page.ClickAsync("button.bulk-delete-hotstrings");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.Locator("[role=\"dialog\"]").GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Deleted 2 hotstring");
    }

    [Fact]
    public async Task DuplicateTrigger_OnPhoneViewport_ShowsInlineConflict()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();
        string trigger = $"dup{Guid.NewGuid():N}"[..12];

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.FillAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]", trigger);
        await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "first");
        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync($".mobile-row:has-text(\"{trigger}\")");

        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.FillAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]", trigger);
        await page.FillAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]", "second");
        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");

        await page.GetByText("Trigger already exists").WaitForAsync();
        Assert.Equal(0, await page.Locator(".hotstring-edit-dialog .mud-alert").CountAsync());
    }
}
