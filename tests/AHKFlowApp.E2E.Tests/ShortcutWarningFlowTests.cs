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

    // Addresses the Windows use of Win+E by id and use label, not by row text. A combination can
    // hold several uses, and each has its own buttons.
    private const string WindowsFileExplorerUse =
        "[data-shortcut-id=\"windows.file-explorer\"][data-used-by=\"Windows\"]";

    [Fact]
    public async Task IgnoringTheWindowsUse_SilencesTheWarning_AndRestoringBringsItBack()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        // Silence the Windows use of Win+E.
        await OpenKnownShortcutsAsync(page, "Win+E");
        await page.ClickAsync($"button.ignore-use{WindowsFileExplorerUse}");
        await page.WaitForSelectorAsync($"button.restore-use{WindowsFileExplorerUse}");

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
        await page.ClickAsync($"button.restore-use{WindowsFileExplorerUse}");
        await page.WaitForSelectorAsync($"button.ignore-use{WindowsFileExplorerUse}");

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
        await page.WaitForSelectorAsync("text=My notes tool");

        await OpenCreateDialogAsync(page);
        await CommitKeyAsync(page, "F7");
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"ctrl-checkbox\"]");

        await page.WaitForSelectorAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
        string warning = await page.InnerTextAsync(".hotkey-edit-dialog [data-test=\"shortcut-warning\"]");
        Assert.Contains("My notes tool uses Ctrl+F7 to open my notes", warning, StringComparison.Ordinal);
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
}
