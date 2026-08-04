using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class HotstringsMobileFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    private static readonly BrowserNewContextOptions TabletViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 768, Height = 1024 },
    };

    // 390px is the iPhone 14 width, and the narrowest phone the mobile list is checked against.
    private static readonly BrowserNewContextOptions NarrowPhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 390, Height = 844 },
    };

    private sealed class OverflowMetrics
    {
        public int BodyOverflow { get; init; }

        public int DocumentOverflow { get; init; }
    }

    private sealed class ColumnMetrics
    {
        public int TableWidth { get; init; }

        public int TriggerWidth { get; init; }

        public int ReplacementWidth { get; init; }

        public int ChevronWidth { get; init; }
    }

    private sealed class TruncationMetrics
    {
        public int ScrollWidth { get; init; }

        public int ClientWidth { get; init; }

        public string WhiteSpace { get; init; } = "";

        public string TextOverflow { get; init; } = "";
    }

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task TabletViewport_DoesNotCreatePageHorizontalOverflow()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(TabletViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring-fab");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");

        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px.");
    }

    [Fact]
    public async Task AddFab_OnPhoneViewport_OpensHotstringDialog()
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
        await page.WaitForSelectorAsync(".hotstring-edit-dialog input[data-test=\"trigger-input\"]");
        await page.WaitForSelectorAsync(".hotstring-edit-dialog textarea[data-test=\"replacement-input\"]");
    }

    [Fact]
    public async Task DesktopCreate_ThenPhoneViewport_ShowsTheNewRowInTheMobileBranch()
    {
        // No viewport option means the default 1280x720, which is wider than the 959.95px
        // breakpoint in Pages/Hotstrings.razor.css. So the page opens on the desktop branch.
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("tr.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "btwx");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", "by the way");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");

        // Resizing fetches nothing. It only changes which branch the CSS shows. So whatever the
        // mobile list holds now is exactly what the desktop mutation left behind.
        await page.SetViewportSizeAsync(375, 812);

        await page.Locator(".mobile-branch tr.mobile-row", new() { HasTextString = "btwx" })
            .WaitForAsync();
    }

    [Fact]
    public async Task NarrowPhoneViewport_MobileList_GivesEachColumnTheWidthTheCssAsksFor()
    {
        await SeedHotstringAsync(fixture, "colw", "column width row");

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(NarrowPhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");

        ILocator row = page.Locator(
            ".mobile-branch tr.mobile-row",
            new() { HasTextString = "column width row" });
        await row.WaitForAsync();

        ColumnMetrics metrics = await row.EvaluateAsync<ColumnMetrics>(
            """
            el => ({
                TableWidth: el.closest('table').clientWidth,
                TriggerWidth: el.querySelector('td.trigger-cell').offsetWidth,
                ReplacementWidth: el.querySelector('td.replacement-cell').offsetWidth,
                ChevronWidth: el.querySelector('td.chevron-cell').offsetWidth
            })
            """);

        // The table is table-layout: fixed, so the browser sizes columns from the header row alone.
        // When the header cells carry no width rule, the three columns split the row evenly and
        // every number below lands near TableWidth / 3. Both assertions catch that.

        // .chevron-cell asks for 24px, plus the 12px padding on each side of the cell.
        Assert.True(
            metrics.ChevronWidth < 60,
            $"Chevron column was {metrics.ChevronWidth}px wide, so the 24px rule did not apply "
            + $"(table {metrics.TableWidth}px, trigger {metrics.TriggerWidth}px).");

        // .trigger-cell asks for 34%, which leaves the replacement column the larger share.
        Assert.True(
            metrics.ReplacementWidth > metrics.TriggerWidth,
            $"Replacement column ({metrics.ReplacementWidth}px) was not wider than the trigger "
            + $"column ({metrics.TriggerWidth}px), so the 34% rule did not apply.");
    }

    [Fact]
    public async Task NarrowPhoneViewport_LongReplacement_TruncatesWithAnEllipsisInsteadOfWrapping()
    {
        // Long enough to overflow the replacement column at 390px, and a single unbroken word, so
        // a wrapped cell would be obvious rather than borderline.
        await SeedHotstringAsync(
            fixture,
            "trunc",
            "truncation row aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(NarrowPhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");

        ILocator cell = page
            .Locator(".mobile-branch tr.mobile-row", new() { HasTextString = "truncation row" })
            .Locator("td.replacement-cell");
        await cell.WaitForAsync();

        TruncationMetrics metrics = await cell.EvaluateAsync<TruncationMetrics>(
            """
            el => ({
                ScrollWidth: el.scrollWidth,
                ClientWidth: el.clientWidth,
                WhiteSpace: getComputedStyle(el).whiteSpace,
                TextOverflow: getComputedStyle(el).textOverflow
            })
            """);

        // nowrap keeps the text on one line, and ellipsis marks where it was cut.
        Assert.Equal("nowrap", metrics.WhiteSpace);
        Assert.Equal("ellipsis", metrics.TextOverflow);

        // scrollWidth over clientWidth means the text really is longer than its column, so the
        // ellipsis is doing work rather than sitting on text that happened to fit.
        Assert.True(
            metrics.ScrollWidth > metrics.ClientWidth,
            $"Replacement text fitted its column (scrollWidth {metrics.ScrollWidth}, "
            + $"clientWidth {metrics.ClientWidth}), so this row proves nothing about truncation.");
    }

    private static async Task SeedHotstringAsync(StackFixture fixture, string trigger, string replacement)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.Hotstrings.Add(new HotstringBuilder()
            .WithOwner(TestAuthHandler.TestOwnerOid)
            .WithTrigger(trigger)
            .WithReplacement(replacement)
            .Build());

        await db.SaveChangesAsync();
    }
}
