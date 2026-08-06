using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class ShortcutWarningFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task WinE_ShowsTheWarningAndStillSaves()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        await OpenCreateDialogAsync(page);

        await CommitKeyAsync(page, "e");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");

        // The notice names what uses the keys, and never promises what will happen.
        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
        string warning = await page.InnerTextAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
        Assert.Contains("Windows uses Win+E to open File Explorer.", warning, StringComparison.Ordinal);
        Assert.DoesNotContain("never", warning, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("will not", warning, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("cannot", warning, StringComparison.OrdinalIgnoreCase);

        // Nothing is blocked. The dialog opens on SendText, which needs its text before Save can
        // succeed — that is ordinary field validation, not the warning.
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E open my notes");
        await page.FillAsync(".hotkey-edit-dialog [data-test=\"text-input\"]", "my notes");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");
    }

    [Fact]
    public async Task ClearingTheModifier_RemovesTheWarning()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        await OpenCreateDialogAsync(page);

        await CommitKeyAsync(page, "e");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");

        await page.UncheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]",
            new PageWaitForSelectorOptions { State = WaitForSelectorState.Detached });
    }

    [Fact]
    public async Task RekeyingAnExistingHotkeyInline_WarnsInTheRow()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        // A SendText hotkey edits inline, in the grid row, never in the dialog. The row changes the
        // key and every modifier, so the row has to warn about them too.
        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "F13");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E inline rekey");
        await page.FillAsync(".hotkey-edit-dialog [data-test=\"text-input\"]", "my notes");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");

        // Scoped to the desktop branch: the mobile branch renders too and is hidden by CSS only.
        await page.Locator(".desktop-branch tr", new() { HasTextString = "E2E inline rekey" })
            .Locator("button.start-edit").ClickAsync();

        // The editing row is addressed by its own class from here on. Its cells hold inputs now, so
        // the description no longer appears as row text and a HasText filter stops matching it —
        // the same reason VersionHistoryFlowTests uses tr.edit-row.
        ILocator row = page.Locator("tr.edit-row");
        await page.WaitForSelectorAsync("tr.edit-row");

        ILocator keyInput = row.Locator("input[data-test=\"key-input\"]");
        await keyInput.ClickAsync();
        await keyInput.FillAsync("e");
        await keyInput.PressAsync("Tab");
        await row.Locator("input[data-test=\"win-checkbox\"]").CheckAsync();

        await Assertions.Expect(row.Locator("[data-test=\"shortcut-warning\"]"))
            .ToContainTextAsync("Windows uses Win+E to open File Explorer.");
    }

    [Fact]
    public async Task AnInlineEditableRow_CanStillOpenTheFullEditor()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "F14");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E full editor");
        await page.FillAsync(".hotkey-edit-dialog [data-test=\"text-input\"]", "my notes");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");

        // Edit sends this row inline, which cannot change the action kind. This button is the way
        // back to the editor that can.
        ILocator row = page.Locator(".desktop-branch tr", new() { HasTextString = "E2E full editor" });
        await row.Locator("button.open-full-editor").ClickAsync();

        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"action-kind-selector\"]");
    }

    // Addresses the Windows use of Win+E by id and use label, not by row text. A combination can
    // hold several uses, and each has its own buttons. The page renders a desktop branch and a
    // mobile branch, both carrying this pair, so the branch is named here once. {0} is the action
    // class. This file runs at the default desktop viewport, so it always means the desktop one.
    private const string WindowsFileExplorerUse =
        ".desktop-branch button{0}[data-shortcut-id=\"windows.file-explorer\"][data-used-by=\"Windows\"]";

    [Fact]
    public async Task IgnoringTheWindowsUse_SilencesTheWarning_AndRestoringBringsItBack()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        // Silence the Windows use of Win+E.
        await OpenKnownShortcutsAsync(page, "Win+E");
        await page.ClickAsync(string.Format(WindowsFileExplorerUse, ".ignore-use"));
        await page.WaitForSelectorAsync(string.Format(WindowsFileExplorerUse, ".restore-use"));

        // The dialog no longer warns. Arm the wait before the dialog opens: the catalog request
        // fires as it loads, and a fixed delay would let a slow response assert on an empty page.
        Task<IResponse> catalogLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/hotkeys/known-shortcuts", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);

        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "e");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");
        await catalogLoaded;

        // Wait for the dialog to say it has decided, for this exact combination. Only then is the
        // absence below a real answer. State.Attached is required: the hook is display:none, so
        // the default Visible would never match. Detached on the warning itself cannot do this
        // job — the warning has never existed, so Playwright would return at once and the test
        // would pass without the feature working.
        await page.WaitForSelectorAsync(
            ".hotkey-edit-dialog [data-test=\"shortcut-warning-checked\"][data-combination=\"Win+E\"]",
            new PageWaitForSelectorOptions { State = WaitForSelectorState.Attached });

        Assert.Null(await page.QuerySelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]"));

        // Bring it back.
        await OpenKnownShortcutsAsync(page, "Win+E");
        await page.ClickAsync(string.Format(WindowsFileExplorerUse, ".restore-use"));
        await page.WaitForSelectorAsync(string.Format(WindowsFileExplorerUse, ".ignore-use"));

        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "e");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
    }

    [Fact]
    public async Task AnOwnerRecord_WarnsOnItsOwnCombination()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        await OpenKnownShortcutsAsync(page);
        await page.ClickAsync("button.add-known-shortcut");

        ILocator keyInput = page.Locator("input[data-test=\"known-shortcut-key-picker\"]");
        await keyInput.ClickAsync();
        await keyInput.FillAsync("F7");
        await keyInput.PressAsync("Tab");

        await page.CheckAsync("input[data-test=\"ctrl-checkbox\"]");
        await page.FillAsync("input[data-test=\"known-shortcut-usedby-input\"]", "My notes tool");
        await page.FillAsync("input[data-test=\"known-shortcut-does-input\"]", "open my notes");
        await page.ClickAsync("button.commit-edit");

        // The table paginates 103 built-in rows plus this one, so search for the new row rather
        // than hunting for it across pages.
        await page.FillAsync("input[data-test=\"known-shortcut-search\"]", "My notes tool");
        await page.WaitForSelectorAsync(".desktop-branch >> text=My notes tool");

        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "F7");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"ctrl-checkbox\"]");

        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
        string warning = await page.InnerTextAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
        Assert.Contains("My notes tool uses Ctrl+F7 to open my notes", warning, StringComparison.Ordinal);
    }

    [Fact]
    public async Task RemappingCapsLockToCtrl_WarnsAboutTheDestination()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "CapsLock");
        await page.ClickAsync(".hotkey-edit-dialog [data-test=\"action-kind-Remap\"]");
        await CommitRemapDestAsync(page, "Ctrl");

        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"destination-warning\"]"))
            .ToContainTextAsync("Shortcuts that use Ctrl may also respond when you hold CapsLock.");

        // F13 is a real registry key that nothing in the catalog uses, so the notice must go.
        await CommitRemapDestAsync(page, "F13");

        // Wait for the decision to name F13 first. Without this, an absent notice could be the
        // older evaluation still on screen rather than a decision about F13.
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"shortcut-warning-checked\"]"))
            .ToHaveAttributeAsync("data-destination", "F13");
        await Assertions.Expect(page.Locator(".hotkey-edit-dialog [data-test=\"destination-warning\"]"))
            .ToHaveCountAsync(0);
    }

    [Fact]
    public async Task AHotkeyOnAKnownShortcut_IsMarkedOnTheList()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        // Win+L is a seeded Protected row: Windows locks the computer with it.
        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "l");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"win-checkbox\"]");
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E lock marker");
        await page.FillAsync(".hotkey-edit-dialog [data-test=\"text-input\"]", "my notes");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");

        // Scoped to the desktop branch: the mobile branch renders too and is hidden by CSS only.
        ILocator marker = page.Locator(".desktop-branch tr", new() { HasTextString = "E2E lock marker" })
            .Locator("[data-test=\"known-shortcut-marker\"]");

        await Assertions.Expect(marker).ToHaveCountAsync(1);

        // The name a screen reader reads is the whole notice, the same sentence the dialog shows.
        string? label = await marker.GetAttributeAsync("aria-label");
        Assert.Contains("Windows uses Win+L to lock the computer.", label, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AHotkeyOnAKeyTheProfileHeaderUses_IsWarnedAbout()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        // Put the Caps Lock layer into the seeded profile's header template.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.start-edit");
        await page.ClickAsync("button.start-edit");
        await page.WaitForSelectorAsync("textarea[data-test=\"profile-header-input\"]");
        await page.FillAsync("textarea[data-test=\"profile-header-input\"]",
            "#Requires AutoHotkey v2.0\n\n*CapsLock::\n{\n    Send \"{Blind}{LCtrl DownR}\"\n}");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Profile updated.");

        // Now bind a hotkey to the same key. "Apply to all profiles" avoids picking one by name.
        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "CapsLock");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"applies-to-all-checkbox\"]");

        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"template-warning\"]");
        string warning = await page.InnerTextAsync(".hotkey-edit-dialog [data-test=\"template-warning\"]");

        Assert.Contains("also uses CapsLock", warning, StringComparison.Ordinal);
        Assert.Contains("Your hotkey may not fire.", warning, StringComparison.Ordinal);
        Assert.DoesNotContain("never", warning, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("will not", warning, StringComparison.OrdinalIgnoreCase);

        // The notice is advice, not a gate: the row still saves.
        await page.FillAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]", "E2E template notice");
        await page.FillAsync(".hotkey-edit-dialog [data-test=\"text-input\"]", "my notes");
        await page.ClickAsync(".hotkey-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey created.");
    }

    // The table holds a row per use, over a hundred of them, and pages at 25. Every row this file
    // acts on is addressed through the search box, never by paging to it.
    private async Task OpenKnownShortcutsAsync(IPage page, string? search = null)
    {
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/known-shortcuts");
        await page.WaitForSelectorAsync("button.reload-known-shortcuts");

        if (search is not null)
            await page.FillAsync("input[data-test=\"known-shortcut-search\"]", search);
    }

    private async Task OpenCreateDialogAsync(IPage page)
    {
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey");
        await page.ClickAsync("button.add-hotkey");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");
    }

    // Fills the MudAutocomplete key picker and commits the typed value by blurring (CoerceValue),
    // the same way HotkeysCrudFlowTests does.
    private static async Task CommitKeyAsync(IPage page, string key)
    {
        ILocator input = page.Locator(".hotkey-edit-dialog input[data-test=\"key-picker\"]");
        await input.ClickAsync();
        await input.FillAsync(key);
        await input.PressAsync("Tab");
    }

    // Same shape as CommitKeyAsync: the remap destination is a MudAutocomplete too, and blurring is
    // what commits the typed value.
    private static async Task CommitRemapDestAsync(IPage page, string key)
    {
        ILocator input = page.Locator(".hotkey-edit-dialog input[data-test=\"remap-dest-picker\"]");
        await input.ClickAsync();
        await input.FillAsync(key);
        await input.PressAsync("Tab");
    }
}
