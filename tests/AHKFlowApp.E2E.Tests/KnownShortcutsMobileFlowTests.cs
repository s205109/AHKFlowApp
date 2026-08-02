using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class KnownShortcutsMobileFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    private static readonly BrowserNewContextOptions TabletViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 768, Height = 1024 },
    };

    private sealed class OverflowMetrics
    {
        public int BodyOverflow { get; init; }

        public int DocumentOverflow { get; init; }
    }

    // Names the Windows use of Win+E in the mobile branch. A combination can hold several uses,
    // and each has its own button. {0} is the action class.
    private const string MobileWindowsFileExplorerUse =
        ".mobile-branch button{0}[data-shortcut-id=\"windows.file-explorer\"][data-used-by=\"Windows\"]";

    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task PhoneViewport_SilencesAUse_AndBringsItBack()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/known-shortcuts");
        await page.WaitForSelectorAsync("button.reload-known-shortcuts");

        // The catalog runs past a hundred uses and the card list pages at 20, so reach the row
        // through the search box rather than paging to it.
        await page.FillAsync("input[data-test=\"known-shortcut-search\"]", "Win+E");

        await page.ClickAsync(string.Format(MobileWindowsFileExplorerUse, ".ignore-use"));
        await page.WaitForSelectorAsync(string.Format(MobileWindowsFileExplorerUse, ".restore-use"));

        await page.ClickAsync(string.Format(MobileWindowsFileExplorerUse, ".restore-use"));
        await page.WaitForSelectorAsync(string.Format(MobileWindowsFileExplorerUse, ".ignore-use"));
    }

    [Fact]
    public async Task PhoneViewport_ShowsWhatUsesTheKeysAndWhatItDoes()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/known-shortcuts");
        await page.WaitForSelectorAsync("button.reload-known-shortcuts");
        await page.FillAsync("input[data-test=\"known-shortcut-search\"]", "Win+E");

        // Addressed by the pair that names the use, not by position. "Win+E" also matches Win+Enter
        // once the search squeezes out spaces and plus signs, so the first row is not this row.
        ILocator row = page.Locator(
            ".mobile-branch .mobile-row:has(code[data-shortcut-id=\"windows.file-explorer\"][data-used-by=\"Windows\"])");

        await Assertions.Expect(row.Locator(".used-by")).ToHaveTextAsync("Windows");
        await Assertions.Expect(row.Locator(".does")).ToHaveTextAsync("open File Explorer");
    }

    [Fact]
    public async Task PhoneViewport_LongOwnerText_DoesNotCreatePageHorizontalOverflow()
    {
        // The phone is the point of this page, so the phone is where overflow is proved. The row
        // is seeded at the real limits and with no spaces to break on: 60 characters of UsedBy,
        // 200 of Does, and every modifier on a long key name.
        await SeedLongOwnerRecordAsync(fixture);

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/known-shortcuts");
        await page.WaitForSelectorAsync("button.reload-known-shortcuts");
        await page.FillAsync("input[data-test=\"known-shortcut-search\"]", LongUsedBy);
        await page.WaitForSelectorAsync(".mobile-branch .mobile-row");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");

        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px.");
    }

    [Fact]
    public async Task TabletViewport_DoesNotCreatePageHorizontalOverflow()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(TabletViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/known-shortcuts");
        await page.WaitForSelectorAsync(".mobile-branch .mobile-row");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");

        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px.");
    }

    // Exactly the column limits, and no spaces, so nothing can wrap on a word boundary:
    // HasMaxLength(60) and HasMaxLength(200) in CustomKnownShortcutConfiguration.cs:15-16.
    private static readonly string LongUsedBy = new('W', 60);

    private static readonly string LongDoes = new('d', 200);

    private static async Task SeedLongOwnerRecordAsync(StackFixture fixture)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.CustomKnownShortcuts.Add(new CustomKnownShortcutBuilder()
            .ForOwner(TestAuthHandler.TestOwnerOid)
            .WithCombination("NumpadEnter", ctrl: true, alt: true, shift: true, win: true)
            .UsedBy(LongUsedBy)
            .Does(LongDoes)
            .Build());

        await db.SaveChangesAsync();
    }
}
