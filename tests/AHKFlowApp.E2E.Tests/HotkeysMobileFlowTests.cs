using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class HotkeysMobileFlowTests(StackFixture fixture) : IAsyncLifetime
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

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey-fab");

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

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey-fab");

        // Add via FAB
        await page.ClickAsync("button.add-hotkey-fab");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "Open palette");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"key-input\"]", "K");
        await page.ClickAsync(".hotkey-edit-dialog input[data-test=\"ctrl-checkbox\"]");
        await page.ClickAsync(".hotkey-edit-dialog input[data-test=\"shift-checkbox\"]");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotkey created.");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"Ctrl+Shift+K\")");

        // Expand row, click edit, change key, save
        await page.ClickAsync(".mobile-row:has-text(\"Ctrl+Shift+K\")");
        await page.WaitForSelectorAsync(".mobile-row-expanded button.start-edit");
        await page.ClickAsync(".mobile-row-expanded button.start-edit");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"key-input\"]", "P");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotkey updated.");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"Ctrl+Shift+P\")");

        // Delete via expanded row (row stays expanded after dialog close)
        await page.WaitForSelectorAsync(".mobile-row-expanded button.delete");
        await page.ClickAsync(".mobile-row-expanded button.delete");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.Locator("[role=\"dialog\"]").GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Hotkey deleted.");
    }

    [Fact]
    public async Task BulkDelete_OnPhoneViewport_UsesSelectMode()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");

        // Create two rows via FAB
        foreach ((string desc, string key) in new[] { ("Macro A", "F1"), ("Macro B", "F2") })
        {
            await page.ClickAsync("button.add-hotkey-fab");
            await page.WaitForSelectorAsync(".hotkey-edit-dialog");
            await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", desc);
            await page.FillAsync(".hotkey-edit-dialog input[data-test=\"key-input\"]", key);
            await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
            await page.WaitForSelectorAsync($".mobile-row:has-text(\"{key}\")");
        }

        // Enter select mode + select both
        await page.ClickAsync("button.toggle-select-mode");
        await page.WaitForSelectorAsync("input.row-checkbox");
        foreach (string key in new[] { "F1", "F2" })
            await page.Locator($"xpath=//tr[contains(@class,'mobile-row')][.//code[normalize-space(.)='{key}']]//input[contains(@class,'row-checkbox')]").CheckAsync();

        await page.ClickAsync("button.bulk-delete-hotkeys");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.Locator("[role=\"dialog\"]").GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Deleted 2 hotkey");
    }

}
