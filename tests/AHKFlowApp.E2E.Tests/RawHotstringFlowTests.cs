using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class RawHotstringFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private const string Definition = ":K1000 SE*:ftw::for the win";

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
    public async Task CreateRawViaDialog_WarningAlertMonospaceParsedSummaryMobileBadgeAndByteMatch()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        // A profile is required so the generated profile script has something to byte-match
        // against at the end of the test.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.add-profile");
        await page.ClickAsync("button.add-profile");
        await page.WaitForSelectorAsync("input[data-test=\"profile-name-input\"]");
        await page.FillAsync("input[data-test=\"profile-name-input\"]", "RawFlow");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=RawFlow");

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

        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Raw')");
        await page.WaitForSelectorAsync("[data-test=\"script-warning\"]");

        // Persistent (non-dismissible) warning alert.
        await Assertions.Expect(page.Locator("[data-test=\"script-warning\"]"))
            .ToContainTextAsync("verbatim AutoHotkey definition");
        await Assertions.Expect(page.Locator("[data-test=\"script-warning\"] button")).ToHaveCountAsync(0);

        // The trigger field is hidden for Raw — the trigger is derived from the definition.
        await Assertions.Expect(page.Locator("input[data-test=\"trigger-input\"]")).ToHaveCountAsync(0);

        ILocator definition = page.Locator("textarea[data-test=\"replacement-input\"]");

        // Larger monospace editor for Raw.
        string fontFamily = await definition.EvaluateAsync<string>("el => getComputedStyle(el).fontFamily");
        Assert.Contains("monospace", fontFamily, StringComparison.OrdinalIgnoreCase);

        await definition.FillAsync(Definition);

        // Server-derived parsed summary (trigger + option tokens) appears below the textarea by
        // default — the preview panel need not be expanded first.
        await Assertions.Expect(page.Locator("[data-test=\"raw-summary\"]")).ToContainTextAsync("ftw");
        await Assertions.Expect(page.Locator("[data-test=\"raw-summary\"]")).ToContainTextAsync("K1000");

        await page.ClickAsync("[data-test=\"ahk-preview\"] .mud-expand-panel-header");
        await page.WaitForSelectorAsync("[data-test=\"preview-snippet\"]");

        // Verbatim passthrough — the definition is emitted exactly as typed.
        await Assertions.Expect(page.Locator("[data-test=\"preview-snippet\"]")).ToContainTextAsync(Definition);

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");
        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px with the preview expanded.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px with the preview expanded.");

        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        // Collapsed mobile row (keyed by the derived trigger) shows the Raw warning badge.
        await page.WaitForSelectorAsync("tr.mobile-row:has-text(\"ftw\")");
        await Assertions.Expect(
            page.Locator("tr.mobile-row:has-text(\"ftw\") [data-test=\"script-badge-collapsed\"]")).ToBeVisibleAsync();

        // Byte-match the downloaded profile script — the verbatim Raw line must appear exactly.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");

        IDownload download = await page.RunAndWaitForDownloadAsync(() =>
            page.ClickAsync("button.download-profile"));

        string path = await download.PathAsync()
            ?? throw new InvalidOperationException("Download produced no file path.");
        byte[] bytes = await File.ReadAllBytesAsync(path);
        string content = System.Text.Encoding.UTF8.GetString(bytes);

        Assert.Contains(Definition, content, StringComparison.Ordinal);
    }
}
