using System.Text;
using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.UI.Blazor.Components.Hotstrings;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Backlog 172. MudBlazor gives a text field maxlength=524288 unless the page sets one, and the
// browser cuts a longer paste without a word. Only a real browser applies maxlength, so only this
// suite proves the import box keeps a whole script.
//
// These tests paste with Control+V, as a person does. FillAsync types the text through Chrome's
// insertText, which adds a multi-line text one line at a time. In this dialog that took 15 s for
// 400,000 characters and more than 60 s for 1 MiB. A real paste of the same 1 MiB took 0.5 s.
// Headless Chromium keeps its own clipboard, so a run never touches the machine's clipboard.
[Collection(E2ECollectionB.Name)]
public sealed class HotstringImportPasteFlowTests(StackFixtureB fixture) : IAsyncLifetime
{
    private const string ScriptBox = "textarea[data-test=\"import-script\"]";

    // 1280 px is above the breakpoint where the page switches to the mobile list, so the desktop
    // Import button is the visible one.
    private static readonly BrowserNewContextOptions DesktopViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 1280, Height = 800 },
    };

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task PasteAtTheServerLimit_KeepsTheWholeScriptAndPreviewsIt()
    {
        string script = BuildScript(HotstringImportDialog.MaxScriptLength);
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);
        IPage page = await OpenImportDialogAsync(ctx);

        await PasteAsync(ctx, page, script);

        Assert.Equal(script.Length, (await page.Locator(ScriptBox).InputValueAsync()).Length);
        await Assertions.Expect(page.Locator(".import-too-large")).ToHaveCountAsync(0);

        await page.ClickAsync("button.preview-import");
        await Assertions.Expect(page.Locator(".import-summary"))
            .ToContainTextAsync("1 ready", new() { Timeout = 30_000 });
    }

    [Fact]
    public async Task PasteAboveTheServerLimit_KeepsTheTextAndShowsTooLargeMessage()
    {
        string script = BuildScript(HotstringImportDialog.MaxScriptLength + 1);
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);
        IPage page = await OpenImportDialogAsync(ctx);

        await PasteAsync(ctx, page, script);

        Assert.Equal(script.Length, (await page.Locator(ScriptBox).InputValueAsync()).Length);
        await Assertions.Expect(page.Locator(".import-too-large"))
            .ToContainTextAsync("This script is too large to import.");
        await Assertions.Expect(page.Locator("button.preview-import")).ToBeDisabledAsync();
    }

    private async Task<IPage> OpenImportDialogAsync(IBrowserContext ctx)
    {
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        await page.ClickAsync("button.import-hotstrings");
        await page.WaitForSelectorAsync(ScriptBox);
        return page;
    }

    private static async Task PasteAsync(IBrowserContext ctx, IPage page, string script)
    {
        await ctx.GrantPermissionsAsync(["clipboard-read", "clipboard-write"]);
        await page.EvaluateAsync("text => navigator.clipboard.writeText(text)", script);
        await page.Locator(ScriptBox).FocusAsync();
        await page.Keyboard.PressAsync("Control+V");
    }

    // One real hotstring, then comment lines up to the exact length. The parser skips comment
    // lines, so the preview finds one row however long the padding is. Line feeds only: a
    // textarea stores line breaks as a single line feed, so the browser and .NET agree on length.
    private static string BuildScript(int length)
    {
        StringBuilder script = new("::zq172::import paste box\n");
        string commentLine = "; " + new string('x', 997) + "\n";
        while (script.Length + commentLine.Length < length)
            script.Append(commentLine);

        // The loop leaves between 1 and 1,000 characters to fill, so this last comment is never empty.
        int rest = length - script.Length;
        script.Append(';').Append('x', rest - 1);
        return script.ToString();
    }
}
