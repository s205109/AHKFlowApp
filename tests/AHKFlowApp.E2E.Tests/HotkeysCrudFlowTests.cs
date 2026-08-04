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

    [Fact]
    public async Task CreateHotkeyLimitedToOneProgram_PreviewWrapsSnippetInHotIf()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E notepad only");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "n");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Run\"]");
        await SelectRunTargetKindAsync(page, "Application");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");

        // Same reason as the flow above: open the preview before the debounced fields are filled.
        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"ahk-preview\"] .mud-expand-panel-header");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"run-target-input\"]", "notepad");

        // Limit the hotkey to one program. The match type defaults to Program, so only the value
        // needs filling in.
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"context-switch\"]");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog input[data-test=\"context-value-input\"]");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"context-value-input\"]", "notepad.exe");

        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-snippet\"]"))
            .ToContainTextAsync("#HotIf WinActive(\"ahk_exe notepad.exe\")");

        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");

        ILocator row = page.Locator(".desktop-branch tr", new() { HasTextString = "E2E notepad only" });
        await row.WaitForAsync();
        await row.Locator(".context-icon").WaitForAsync();
    }

    // Backlog 037: a Raw body that injects a second top-level definition must be rejected before
    // the preview can generate. The preview panel's blocked message only appears while it is
    // expanded (HotkeyEditDialog.razor:613-616), so the flow opens it before typing the body.
    //
    // The flow goes through a VALID body first and waits for the generated snippet. An empty Raw
    // body is itself invalid ("Raw requires an action body.", HotkeyRules.cs:102-103), so asserting
    // the blocked message straight after typing would also pass while that first error was still
    // on screen — the body field debounces for 300 ms (HotkeyEditDialog.razor:175). Proving the
    // snippet rendered first means the blocked message can only come from the injected definition.
    //
    // This asserts only the panel-level message. The field-level highlight on the Body textarea is
    // a separate concern, covered by RawBodyPreviewError_ShowsInlineOnTheBodyField below.
    [Fact]
    public async Task RawBodyInjectingAnotherHotkey_BlocksPreviewGeneration()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E bad raw body");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "j");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Raw\"]");
        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"ahk-preview\"] .mud-expand-panel-header");

        // A one-line body the guard accepts — the preview must generate before anything is blocked.
        await page.FillAsync(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]", "return");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-snippet\"]"))
            .ToContainTextAsync("j::return");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-blocked\"]"))
            .ToHaveCountAsync(0);

        // Same body plus an injected second definition — now the preview must be blocked.
        await page.FillAsync(
            ".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]",
            "return\n^a::Run(\"calc\")");

        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-blocked\"]"))
            .ToContainTextAsync("Fix the highlighted fields to see the generated code.");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-snippet\"]"))
            .ToHaveCountAsync(0);
    }

    // Backlog 051: the Body field's own inline error, on the preview path. A bUnit test cannot
    // pin this — it renders the field correctly whether or not the browser does — so the guard
    // has to run in a real browser against the real validation rule.
    [Fact]
    public async Task RawBodyPreviewError_ShowsInlineOnTheBodyField()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E raw inline error");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "j");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Raw\"]");
        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"ahk-preview\"] .mud-expand-panel-header");

        await page.FillAsync(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]", "return");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-snippet\"]"))
            .ToContainTextAsync("j::return");

        await page.FillAsync(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]", "if (1) {");

        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"preview-blocked\"]"))
            .ToContainTextAsync("Fix the highlighted fields to see the generated code.");

        await Assertions.Expect(page.Locator(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]"))
            .ToHaveAttributeAsync("aria-invalid", "true");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog .raw-body-wrap .mud-input-helper-text"))
            .ToContainTextAsync("Raw body braces are unbalanced.");
    }

    // Backlog 051, second half: Save routes a Body error into _saveFieldErrors
    // (HotkeyEditDialog.razor:414) rather than the generic alert, so the field is the only place
    // the user can learn why Save did nothing. The preview panel stays collapsed here on purpose —
    // that way only the Save response can produce the message being asserted.
    [Fact]
    public async Task RawBodySaveError_ShowsInlineOnTheBodyField()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");

        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");

        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E raw save error");
        await CommitKeyAsync(page, ".hotkey-edit-dialog input[data-test=\"key-picker\"]", "j");

        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Raw\"]");
        await page.FillAsync(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]", "if (1) {");

        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");

        await Assertions.Expect(page.Locator(".hotkey-edit-dialog .raw-body-wrap .mud-input-helper-text"))
            .ToContainTextAsync("Raw body braces are unbalanced.");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]"))
            .ToHaveAttributeAsync("aria-invalid", "true");

        // The message must still be there once the field's debounce can no longer be pending.
        // Filling the body arms a 300 ms timer (HotkeyEditDialog.razor:173-175) whose elapsed
        // handler calls ClearSaveError("Body") (razor:375-379) — the same key the Save response
        // writes (razor:414). Playwright's Expect polls, so the assertions above would go green on
        // a message that vanished a moment later. Re-checking after the window closes is what
        // makes this test prove the user can actually read the message.
        await page.WaitForTimeoutAsync(1500);
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog .raw-body-wrap .mud-input-helper-text"))
            .ToContainTextAsync("Raw body braces are unbalanced.");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog textarea[data-test=\"raw-body-input\"]"))
            .ToHaveAttributeAsync("aria-invalid", "true");

        // The rejected hotkey must not have been created, and the dialog must still be open on it.
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog")).ToBeVisibleAsync();
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
