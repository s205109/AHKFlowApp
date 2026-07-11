using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class MacroHotstringFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
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
    public async Task CreateMacroViaDialog_CaretInsertion_PreviewAndSave()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        Task<IResponse> profilesLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/profiles", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);
        Task<IResponse> categoriesLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/categories", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");
        await Task.WhenAll(profilesLoaded, categoriesLoaded);

        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");

        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Macro')");
        await page.WaitForSelectorAsync("[data-test=\"macro-toolbar\"]");

        await page.FillAsync("input[data-test=\"trigger-input\"]", "htag");

        ILocator replacement = page.Locator("textarea[data-test=\"replacement-input\"]");
        await replacement.FillAsync("<b></b>");
        // Place the caret between the tags, then insert the cursor token via the toolbar.
        await replacement.EvaluateAsync("el => { el.focus(); el.setSelectionRange(3, 3); }");
        await page.ClickAsync("[data-test=\"macro-toolbar\"] button:has-text('Cursor')");

        ILocator cursorButton = page.Locator("[data-test=\"macro-toolbar\"] button:has-text('Cursor')");
        await Assertions.Expect(replacement).ToHaveValueAsync("<b>{{cursor}}</b>");
        // The Cursor button disables once the bound model contains a cursor token — this
        // proves the insertion flowed through Blazor's binding, not just the DOM.
        await Assertions.Expect(cursorButton).ToBeDisabledAsync();

        await page.ClickAsync("[data-test=\"ahk-preview\"] .mud-expand-panel-header");
        await page.WaitForSelectorAsync("[data-test=\"preview-snippet\"]");

        ILocator snippet = page.Locator("[data-test=\"preview-snippet\"]");
        // ":?:" — the dialog's defaults include trigger-inside-word, emitted as the ? option.
        await Assertions.Expect(snippet).ToContainTextAsync(":?:htag::");
        await Assertions.Expect(snippet).ToContainTextAsync("SendText \"<b></b>\"");
        await Assertions.Expect(snippet).ToContainTextAsync("Send \"{Left 4}\"");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");
        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px with the preview expanded.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px with the preview expanded.");

        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        await page.WaitForSelectorAsync("tr.mobile-row:has-text(\"htag\")");
        ILocator replacementCell = page.Locator("tr.mobile-row:has-text(\"htag\") td.replacement-cell");
        await Assertions.Expect(replacementCell).ToHaveTextAsync("<b>{{cursor}}</b>");
    }
}
