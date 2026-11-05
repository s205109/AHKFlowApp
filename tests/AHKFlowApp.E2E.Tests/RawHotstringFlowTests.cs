using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionC.Name)]
public sealed class RawHotstringFlowTests(StackFixtureC fixture) : IAsyncLifetime
{
    private const string Definition = ":K1000 SE*:ftw::for the win";
    private const string ContinuationDefinition = ":*:col::\n(\nred\ngreen\nblue\n)";

    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    private static readonly BrowserNewContextOptions DesktopViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 1280, Height = 900 },
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

        // A profile is required so the generated profile script has something to byte-match
        // against at the end of the test. It is seeded, not created in the browser: the profile
        // create flow is covered by
        // ProfileCreateDefaultHeaderFlowTests.CreateProfile_WithoutTouchingTheHeader_GeneratesAScriptWithTheDirectives.
        await using (AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Profiles.Add(new ProfileBuilder()
                .WithOwner(TestAuthHandler.TestOwnerOid)
                .WithName("RawFlow")
                .Build());
            await db.SaveChangesAsync();
        }

        IPage page = await FirstPageLoad.OpenAsync(
            ctx, $"{fixture.Spa.BaseUrl}/hotstrings", "/api/v1/profiles", "/api/v1/categories");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");

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

        // Collapsed mobile row (keyed by the derived trigger) shows the Raw kind chip, which carries
        // the warning icon and the accessible warning text.
        await page.WaitForSelectorAsync("tr.mobile-row:has-text(\"ftw\")");
        await Assertions.Expect(
            page.Locator("tr.mobile-row:has-text(\"ftw\") [data-test=\"raw-kind-chip\"]")).ToBeVisibleAsync();

        // A second Raw hotstring, this time a continuation section. Its summary names the body kind
        // and the line count.
        await page.ClickAsync("button.add-hotstring-fab");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");
        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Raw')");
        await page.WaitForSelectorAsync("[data-test=\"script-warning\"]");

        await page.Locator("textarea[data-test=\"replacement-input\"]").FillAsync(ContinuationDefinition);

        await Assertions.Expect(page.Locator("[data-test=\"raw-summary\"]")).ToContainTextAsync("col");
        await Assertions.Expect(page.Locator("[data-test=\"raw-summary\"]")).ToContainTextAsync("multi-line text (3 lines)");

        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("tr.mobile-row:has-text(\"col\")");

        // Byte-match the downloaded profile script — the verbatim Raw line and the continuation
        // section must both appear exactly.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");

        IDownload download = await page.RunAndWaitForDownloadAsync(() =>
            page.ClickAsync("button.download-profile"));

        string path = await download.PathAsync()
            ?? throw new InvalidOperationException("Download produced no file path.");
        byte[] bytes = await File.ReadAllBytesAsync(path);
        string content = System.Text.Encoding.UTF8.GetString(bytes);

        Assert.Contains(Definition, content, StringComparison.Ordinal);
        Assert.Contains(ContinuationDefinition, content, StringComparison.Ordinal);
    }

    [Fact]
    public async Task PromoteInlineDraftToRawViaDialog_CreatesRawHotstring()
    {
        // Desktop-only flow (P14): start an inline Text draft, promote it to the full dialog via the
        // Tune action, switch the promoted draft to Raw, and save. Covers the promote path the mobile
        // create test can't reach.
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        // Inline Text draft — carry a typed trigger into the promotion.
        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("input[data-test=\"trigger-input\"]");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "seed");

        // Promote to the full dialog (Tune action).
        await page.ClickAsync("button.promote-edit");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");

        // Switch the promoted draft to Raw (empty replacement, so no discard confirmation) and paste a
        // full verbatim definition — the trigger is now derived from the text, not the seeded "seed".
        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Raw')");
        await page.WaitForSelectorAsync("[data-test=\"script-warning\"]");

        ILocator definition = page.Locator(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]");
        await definition.FillAsync(Definition);

        // Parsed summary reflects the derived trigger without expanding the preview panel.
        await Assertions.Expect(page.Locator("[data-test=\"raw-summary\"]")).ToContainTextAsync("ftw");

        await page.ClickAsync(".hotstring-edit-dialog button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        // The new Raw row's Trigger column shows the derived trigger.
        await Assertions.Expect(
            page.Locator(".desktop-branch .hotstrings-grid td[data-label=\"Trigger\"]")).ToContainTextAsync("ftw");
    }

    [Fact]
    public async Task SwitchRawToTextViaDialog_KeepsTheVisibleOptionStates()
    {
        // Backlog 161. The parsing matrix is covered by bUnit; this proves the three checkboxes a
        // person sees after the switch, in a real browser.
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("input[data-test=\"trigger-input\"]");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "seed");

        await page.ClickAsync("button.promote-edit");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog");

        // Into Raw with an empty replacement, so no discard confirmation appears.
        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Raw')");
        ILocator definition = page.Locator(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]");
        await definition.FillAsync(":*C:btw::by the way");

        // Back out to Text. '*' and 'C' are both expressible, so this needs no confirmation.
        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Text')");

        await Assertions.Expect(page.Locator("input[data-test=\"case-sensitive-checkbox\"]")).ToBeCheckedAsync();
        await Assertions.Expect(page.Locator("input[data-test=\"expand-immediately-checkbox\"]")).ToBeCheckedAsync();
        await Assertions.Expect(page.Locator("input[data-test=\"inside-words-checkbox\"]")).Not.ToBeCheckedAsync();
    }
}
