using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class ScriptHotstringFlowTests(StackFixture fixture) : IAsyncLifetime
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
    public async Task CreateScriptViaDialog_WarningAlertMonospacePreviewMobileBadgeAndByteMatch()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        // A profile is required so the generated profile script has something to byte-match
        // against at the end of the test.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.add-profile");
        await page.ClickAsync("button.add-profile");
        await page.WaitForSelectorAsync("input[data-test=\"profile-name-input\"]");
        await page.FillAsync("input[data-test=\"profile-name-input\"]", "Phase5");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Phase5");

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

        await page.ClickAsync(".hotstring-edit-dialog .mud-toggle-item:has-text('Script')");
        await page.WaitForSelectorAsync("[data-test=\"script-warning\"]");

        // Persistent (non-dismissible) warning alert.
        await Assertions.Expect(page.Locator("[data-test=\"script-warning\"]"))
            .ToContainTextAsync("Runs arbitrary AutoHotkey code in the generated script.");
        await Assertions.Expect(page.Locator("[data-test=\"script-warning\"] button")).ToHaveCountAsync(0);

        ILocator replacement = page.Locator("textarea[data-test=\"replacement-input\"]");

        // Larger monospace editor for Script.
        string fontFamily = await replacement.EvaluateAsync<string>("el => getComputedStyle(el).fontFamily");
        Assert.Contains("monospace", fontFamily, StringComparison.OrdinalIgnoreCase);

        await page.FillAsync("input[data-test=\"trigger-input\"]", "~ver");
        await replacement.FillAsync("MsgBox A_AhkVersion");

        // Match spec §7 ex. 7's ":*:~ver::" options exactly (expand immediately, not
        // trigger-inside-word).
        await page.ClickAsync("[data-test=\"expand-immediately-checkbox\"]");
        await page.ClickAsync("[data-test=\"inside-words-checkbox\"]");

        await page.ClickAsync("[data-test=\"ahk-preview\"] .mud-expand-panel-header");
        await page.WaitForSelectorAsync("[data-test=\"preview-snippet\"]");

        ILocator snippet = page.Locator("[data-test=\"preview-snippet\"]");
        await Assertions.Expect(snippet).ToContainTextAsync(":*:~ver::");
        // Exact verbatim brace-body passthrough (HotstringEmitter.BuildScriptBody).
        await Assertions.Expect(snippet).ToContainTextAsync("{\nMsgBox A_AhkVersion\n}");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");
        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px with the preview expanded.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px with the preview expanded.");

        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        // Collapsed mobile row shows the Script warning badge.
        await page.WaitForSelectorAsync("tr.mobile-row:has-text(\"~ver\")");
        await Assertions.Expect(
            page.Locator("tr.mobile-row:has-text(\"~ver\") [data-test=\"script-badge-collapsed\"]")).ToBeVisibleAsync();

        // Byte-match the downloaded profile script against the golden — same generator used by
        // the real .ahk download, so this is the exact snippet the profile script would contain.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("text=Phase5");
        await page.ClickAsync("button.toggle-expand");
        await page.ClickAsync(".profile-preview-pane .mud-expand-panel-header");
        await page.ClickAsync("button.profile-preview-refresh");
        await page.WaitForSelectorAsync(".profile-preview-script");

        await Assertions.Expect(page.Locator(".profile-preview-script"))
            .ToContainTextAsync(":*:~ver::\n{\nMsgBox A_AhkVersion\n}");
    }
}
