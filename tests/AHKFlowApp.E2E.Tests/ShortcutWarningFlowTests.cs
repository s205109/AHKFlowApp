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
