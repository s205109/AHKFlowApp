using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

/// <summary>
/// Covers the two surfaces the snap work added that unit and bUnit tests structurally cannot reach:
/// a Window action whose emitted body is multi-line (every other kind is one line), and the Win+Arrow
/// advisory, whose whole job is to appear and disappear as the user toggles controls in a real browser.
/// The preview here is served by the API, so a green run also proves HotkeyEmitter's snap block
/// survives the round trip over HTTP and into the DOM unmangled.
/// </summary>
[Collection(E2ETestCollection.Name)]
public sealed class WindowSnapFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task CreateSnapLeftHotkey_PreviewKeepsBlockBodyLines_ThenGridShowsWindowAction()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E snap left");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "Left");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Window\"]");
        await SelectWindowOpAsync(page, "Snap left", expectedValue: "SnapLeft");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"ctrl-checkbox\"]");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"alt-checkbox\"]");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"ahk-preview\"] .mud-expand-panel-header");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"preview-snippet\"]");

        // InnerText, not TextContent or ToContainTextAsync: those two would pass on a single collapsed
        // line. InnerText is rendered text, so the newlines only survive it while the snippet really
        // lays out as four lines — which is what makes this assertion worth running in a browser at
        // all. Regressing .preview-snippet to white-space: normal, or the <pre> to a <div>, fails here
        // and nowhere else in the suite.
        ILocator snippet = page.Locator(".hotkey-edit-dialog [data-test=\"preview-snippet\"]");
        string rendered = (await snippet.InnerTextAsync()).ReplaceLineEndings("\n");

        rendered.Should().Contain(
            "^!Left::{\n" +
            "    WinRestore(\"A\")\n" +
            "    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)\n" +
            "    WinMove(l, t, (r - l) // 2, b - t, \"A\")\n" +
            "}");

        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");

        // Scoped to the desktop branch: both branches are in the DOM and the mobile one is hidden by
        // CSS alone, so an unscoped selector matches twice.
        ILocator row = page.Locator(".desktop-branch tr", new() { HasTextString = "E2E snap left" });
        await row.WaitForAsync();

        (await row.Locator("[data-test=\"action-chip\"]").InnerTextAsync()).Should().Contain("Window");
        await Assertions.Expect(row).ToContainTextAsync("Snap left");
    }

    [Fact]
    public async Task SendKeysWinPlusArrow_ShowsAdvisoryUntilWinCleared_AndStillSaves()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E win arrow send");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "n");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-SendKeys\"]");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"send-win-checkbox\"]");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"send-key-picker\"]", "Left");

        ILocator warning = page.Locator(".hotkey-edit-dialog [data-test=\"send-win-arrow-warning\"]");
        await Assertions.Expect(warning).ToBeVisibleAsync();
        await Assertions.Expect(warning).ToContainTextAsync("won't snap or resize the window");
        await Assertions.Expect(warning).ToContainTextAsync("Snap left");

        // Clearing Win must retract the advisory, not just stop adding it — the alert occupies flow
        // above the key picker, so a stuck alert permanently displaces the control beneath it.
        await page.UncheckAsync(".hotkey-edit-dialog input[data-test=\"send-win-checkbox\"]");
        await Assertions.Expect(warning).ToBeHiddenAsync();

        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"send-win-checkbox\"]");
        await Assertions.Expect(warning).ToBeVisibleAsync();

        // Advisory only. Save has to go through with the warning on screen, or it has quietly become
        // a validation rule.
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");

        ILocator row = page.Locator(".desktop-branch tr", new() { HasTextString = "E2E win arrow send" });
        await row.WaitForAsync();

        (await row.Locator("[data-test=\"action-chip\"]").InnerTextAsync()).Should().Contain("Send keys");
        await Assertions.Expect(row).ToContainTextAsync("#{Left}");
    }

    // Fills a MudAutocomplete key picker and commits the typed value by blurring (CoerceValue).
    private static async Task CommitKeyAsync(IPage page, string selector, string key)
    {
        ILocator input = page.Locator(selector);
        await input.ClickAsync();
        await input.FillAsync(key);
        await input.PressAsync("Tab");
    }

    // Opens the Window op MudSelect and picks the named option from its body-level popover. MudSelect
    // can drop the first click while the popover animates in, leaving the value silently unset, so
    // the open+pick is retried until the value commits.
    //
    // Two MudSelect details this has to work around, both learned the hard way:
    //  - UserAttributes land on MudSelect's *hidden* input, which can never be clicked. The click has
    //    to target the enclosing .mud-input-control instead.
    //  - That hidden input's value is the enum name ("SnapLeft"), not the item label ("Snap left"), so
    //    the commit check compares against `expectedValue`. HotkeysCrudFlowTests gets away with
    //    comparing to a label only because RunTargetKind.Application's name and label are identical.
    private static async Task SelectWindowOpAsync(IPage page, string label, string expectedValue)
    {
        ILocator hidden = page.Locator(".hotkey-edit-dialog [data-test=\"window-op-select\"]");
        ILocator control = page.Locator(".hotkey-edit-dialog .mud-input-control:has([data-test=\"window-op-select\"])");
        ILocator option = page.Locator($".mud-list-item:has-text(\"{label}\")");

        for (int attempt = 0; attempt < 5; attempt++)
        {
            await control.ClickAsync();
            await option.WaitForAsync(new() { State = WaitForSelectorState.Visible });
            await option.ClickAsync();

            if (await hidden.GetAttributeAsync("value") == expectedValue)
                return;
        }

        (await hidden.GetAttributeAsync("value")).Should().Be(expectedValue, "the Window op must commit");
    }
}
