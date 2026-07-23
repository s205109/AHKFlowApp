using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class HotkeysCrudFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task CreateRunHotkey_ShowsPreviewThenAppearsInGridWithActionChip()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E open notepad");

        // key-picker is a MudAutocomplete with CoerceValue: FillAsync alone sets the text but does
        // not commit the Value. Blurring the field coerces the typed key onto the bound Value —
        // the picker's own "type a vk/sc code" escape hatch. The #n:: preview and the Win+N grid
        // cell below both fail if this did not commit, so a green run proves the commit happened.
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "n");

        // Run's fields only exist once Run is the selected kind. A Run action requires both a
        // target and a target kind (HotkeyRules: "Run requires a valid run target kind."), so the
        // flow picks the kind exactly as a user would — otherwise the preview stays blocked.
        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Run\"]");
        await SelectRunTargetKindAsync(page, "Application");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");

        // Expand the preview BEFORE filling the run target. The target field's @bind-Value is
        // debounced (300ms), so its refresh only fires while the panel is already open — filling
        // it beforehand would leave the preview stale with an empty target.
        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"ahk-preview\"] .mud-expand-panel-header");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"run-target-input\"]", "notepad");

        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"preview-snippet\"]");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-snippet\"]"))
            .ToContainTextAsync("#n::Run(\"notepad\")");

        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotkey created.");

        // Grid assertions are scoped to the desktop branch: both branches render into the DOM and
        // the mobile branch is hidden only by CSS, so an unscoped selector could match twice.
        ILocator row = page.Locator(".desktop-branch tr", new() { HasTextString = "E2E open notepad" });
        await row.WaitForAsync();

        (await row.Locator("[data-test=\"action-chip\"]").InnerTextAsync()).Should().Contain("Run");
        await Assertions.Expect(row.Locator("code")).ToContainTextAsync("Win+N");
    }

    // Fills a MudAutocomplete key picker and commits the typed value by blurring (CoerceValue).
    private static async Task CommitKeyAsync(IPage page, string selector, string key)
    {
        ILocator input = page.Locator(selector);
        await input.ClickAsync();
        await input.FillAsync(key);
        await input.PressAsync("Tab");
    }

    // Opens the Run target-kind MudSelect and picks the named option from its popover. The
    // options render as .mud-list-item in a body-level popover; wait for the one we want to be
    // visible before clicking so the click lands after the popover has opened.
    private static async Task SelectRunTargetKindAsync(IPage page, string label)
    {
        ILocator select = page.Locator(".hotkey-edit-dialog [data-test=\"run-target-kind-select\"]");
        ILocator option = page.Locator($".mud-list-item:has-text(\"{label}\")");

        // MudSelect can miss the very first click while its popover is still animating in, which
        // silently leaves the value unset. Retry the open+pick until the input reflects the label.
        for (int attempt = 0; attempt < 5; attempt++)
        {
            await select.ClickAsync();
            await option.WaitForAsync(new() { State = WaitForSelectorState.Visible });
            await option.ClickAsync();

            if (await select.InputValueAsync() == label)
                return;
        }

        (await select.InputValueAsync()).Should().Be(label, "the Run target kind must commit");
    }
}
