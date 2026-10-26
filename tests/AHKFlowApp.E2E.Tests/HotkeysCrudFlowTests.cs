using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using FluentAssertions.Execution;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionB.Name)]
public sealed class HotkeysCrudFlowTests(StackFixtureB fixture) : IAsyncLifetime
{
    // 1280 px is the width the grid's CSS comments are measured at, and it is well above the
    // 959.95 px breakpoint where the page switches to the mobile list.
    private static readonly BrowserNewContextOptions DesktopViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 1280, Height = 800 },
    };

    // 1240 px still shows the desktop grid, and its Profiles column is narrower than at 1280 px.
    // The chip test runs here because a 12% column fails and 14% passes, each by about 4 px.
    private static readonly BrowserNewContextOptions NarrowDesktopViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 1240, Height = 800 },
    };

    private sealed class ChipFit
    {
        public double ChipRight { get; init; }

        public double ContentRight { get; init; }
    }

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task CreateRunHotkey_ShowsPreviewThenAppearsInGridWithActionChip()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
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

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
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

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
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

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
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

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
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

    // Backlog 167. MudBlazor's SelectColumn writes an inline width:0% on its header cell. This grid
    // is table-layout: fixed, so the column collapsed to 0 px and the Description cell covered
    // every row checkbox. CheckAsync clicks only when the checkbox itself is the hit target, so it
    // times out while anything covers it. Never pass Force here: Force skips that check. The phone
    // viewport uses its own select mode and never showed this bug.
    [Fact]
    public async Task BulkDelete_OnDesktopViewport_SelectsRowsWithTheirCheckboxes()
    {
        // Description is the cell that covered the checkbox, so one row carries the longest
        // description the database allows: 200 characters.
        string longDescription = "Macro A " + new string('x', 192);
        await SeedHotkeysAsync(fixture, (longDescription, "F1"), ("Macro B", "F2"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");

        // Both branches render into the DOM, and the mobile list has a bulk-delete button of its
        // own, so every locator here is scoped to the desktop branch.
        ILocator rowA = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Macro A" });
        ILocator rowB = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Macro B" });
        ILocator bulkDelete = page.Locator(".desktop-branch button.bulk-delete-hotkeys");
        await rowA.WaitForAsync();
        await rowB.WaitForAsync();

        await rowA.Locator("td:first-child input[type=checkbox]").CheckAsync();
        await Assertions.Expect(bulkDelete).ToContainTextAsync("Delete 1 selected");
        await rowB.Locator("td:first-child input[type=checkbox]").CheckAsync();
        await Assertions.Expect(bulkDelete).ToContainTextAsync("Delete 2 selected");

        await bulkDelete.ClickAsync();
        ILocator dialog = page.Locator("[role=\"dialog\"]");
        await dialog.WaitForAsync();
        await dialog.GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Deleted 2 hotkey");
        await Assertions.Expect(rowA).ToHaveCountAsync(0);
        await Assertions.Expect(rowB).ToHaveCountAsync(0);
    }

    // Backlog 167. The header's select-all checkbox lives in the same column, so the collapsed
    // width covered it too.
    [Fact]
    public async Task SelectAll_OnDesktopViewport_SelectsEveryRowOnThePage()
    {
        await SeedHotkeysAsync(fixture, ("Macro A", "F1"), ("Macro B", "F2"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
        ILocator rowA = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Macro A" });
        ILocator rowB = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Macro B" });
        ILocator checkboxA = rowA.Locator("td:first-child input[type=checkbox]");
        ILocator checkboxB = rowB.Locator("td:first-child input[type=checkbox]");
        await rowA.WaitForAsync();
        await rowB.WaitForAsync();

        // Checking the rows start unticked means the ticks below can only come from select-all.
        await Assertions.Expect(checkboxA).Not.ToBeCheckedAsync();
        await Assertions.Expect(checkboxB).Not.ToBeCheckedAsync();

        await page.Locator(".desktop-branch thead th:first-child input[type=checkbox]").CheckAsync();

        await Assertions.Expect(page.Locator(".desktop-branch button.bulk-delete-hotkeys"))
            .ToContainTextAsync("Delete 2 selected");

        // The count proves the page's selection changed. The row ticks prove the owner can see it.
        await Assertions.Expect(checkboxA).ToBeCheckedAsync();
        await Assertions.Expect(checkboxB).ToBeCheckedAsync();
    }

    // Backlog 190. Four 48 px buttons did not fit the 160 px Actions column. In view mode the last
    // one ended 56 px past its cell, and the cell cut it off. Edit mode shows two buttons and
    // already fit; it is measured so that a later change cannot break it. Both states are
    // measured before any assertion runs, so one red run shows each state that fails.
    [Fact]
    public async Task RowButtons_OnDesktopViewport_SitInsideTheActionsCellOnOneLine()
    {
        // The builder's default action is Run, and F1 is a known key, so this row edits inline.
        await SeedHotkeysAsync(fixture, ("Macro A", "F1"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
        ILocator row = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Macro A" });
        await row.Locator("button.open-full-editor").WaitForAsync();
        ActionsCellLayout view = await ActionsCell.MeasureAsync(page, row, "button.open-full-editor");

        await row.Locator("button.start-edit").ClickAsync();
        ILocator editRow = page.Locator(".desktop-branch tr.edit-row");
        await editRow.Locator("button.cancel-edit").WaitForAsync();
        ActionsCellLayout edit = await ActionsCell.MeasureAsync(page, editRow, "button.cancel-edit");

        using (new AssertionScope())
        {
            ActionsCell.AssertInsideItsCellOnOneLine("view mode", view, expectedButtons: 4);
            ActionsCell.AssertInsideItsCellOnOneLine("edit mode", edit, expectedButtons: 2);
        }
    }

    // Backlog 190. The wider Actions column leaves less room for the percentage columns. With
    // Profiles at 12%, the "All profiles" chip ran into its cell's right padding at this window;
    // at 14% it fits. The check uses the content box, not the cell, because the cell's padding
    // would hide a chip that had run into it.
    [Fact]
    public async Task AllProfilesChip_OnNarrowDesktopViewport_EndsInsideItsContentBox()
    {
        // The builder's default row applies to all profiles, so it shows the chip.
        await SeedHotkeysAsync(fixture, ("Macro A", "F1"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(NarrowDesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotkeys");
        ILocator row = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Macro A" });
        await row.Locator(".mud-chip", new() { HasTextString = "All profiles" }).WaitForAsync();

        // The chip's width depends on its font, and the page loads Roboto with display=swap.
        await page.EvaluateAsync("() => document.fonts.ready.then(() => true)");

        ILocator cell = row.Locator("td").Filter(new() { Has = page.Locator(".mud-chip", new() { HasTextString = "All profiles" }) });
        ChipFit fit = await cell.EvaluateAsync<ChipFit>(
            "td => ({ ChipRight: td.querySelector('.mud-chip').getBoundingClientRect().right, "
            + "ContentRight: td.getBoundingClientRect().right - parseFloat(getComputedStyle(td).paddingRight) })");

        fit.ChipRight.Should().BeLessThanOrEqualTo(fit.ContentRight, "the All profiles chip must end inside its cell's content box");
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

    private static async Task SeedHotkeysAsync(StackFixture fixture, params (string Description, string Key)[] hotkeys)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        foreach ((string description, string key) in hotkeys)
        {
            db.Hotkeys.Add(new HotkeyBuilder()
                .WithOwner(TestAuthHandler.TestOwnerOid)
                .WithDescription(description)
                .WithKey(key)
                .Build());
        }

        await db.SaveChangesAsync();
    }
}
