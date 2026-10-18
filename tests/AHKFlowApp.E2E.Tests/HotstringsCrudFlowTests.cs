using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using FluentAssertions.Execution;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionC.Name)]
public sealed class HotstringsCrudFlowTests(StackFixtureC fixture) : IAsyncLifetime
{
    // 1280 px is well above the 959.95 px breakpoint where the page switches to the mobile list.
    private static readonly BrowserNewContextOptions DesktopViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 1280, Height = 800 },
    };

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task CreateEditDelete_DrivesBlazorSpaThroughBrowser()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("tr.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "btw");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", "by the way");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"btw\")");
        // A new hotstring starts with Trigger inside words off, so the saved row shows no ? glyph.
        // After a create, the page reloads the grid from the API, so this reads the saved value.
        await Assertions.Expect(page.Locator("tbody tr:has-text(\"btw\") .option-glyphs")).ToHaveTextAsync("");

        Assert.True(await page.IsVisibleAsync("text=by the way"));

        await page.ClickAsync("button.edit");
        await page.WaitForSelectorAsync("tr.edit-row");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", "by the way!");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring updated.");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"by the way!\")");

        await page.ClickAsync("button.delete");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        // Scoped to the dialog: the row's own button is named "Delete btw", which also matches.
        await page.Locator("[role=\"dialog\"]").GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Hotstring deleted.");
        await page.WaitForSelectorAsync("text=No hotstrings yet.");
    }

    // Backlog 180. MudBlazor's SelectColumn writes an inline width:0% on its header cell, and this
    // grid is table-layout: fixed. Hotstrings.razor pins the column to 56 px. Without that pin the
    // column collapses to 0 px and the Trigger cell covers every row checkbox. CheckAsync clicks
    // only when the checkbox itself is the hit target, so it times out while anything covers it.
    // Never pass Force here: Force skips that check. Backlog 167 found this bug on the hotkeys grid.
    [Fact]
    public async Task BulkDelete_OnDesktopViewport_SelectsRowsWithTheirCheckboxes()
    {
        // Trigger is the cell beside the checkbox, so one row carries the longest trigger the
        // database allows: 50 characters.
        string longTrigger = "rowa" + new string('x', 46);
        await SeedHotstringsAsync(fixture, (longTrigger, "Row A text"), ("rowb", "Row B text"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");

        // Both branches render into the DOM, and the mobile list has a bulk-delete button of its
        // own, so every locator here is scoped to the desktop branch.
        ILocator rowA = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Row A text" });
        ILocator rowB = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Row B text" });
        ILocator bulkDelete = page.Locator(".desktop-branch button.bulk-delete-hotstrings");
        await rowA.WaitForAsync();
        await rowB.WaitForAsync();

        await rowA.Locator("td:first-child input[type=checkbox]").CheckAsync();
        await Assertions.Expect(bulkDelete).ToContainTextAsync("Delete 1 selected");
        await rowB.Locator("td:first-child input[type=checkbox]").CheckAsync();
        await Assertions.Expect(bulkDelete).ToContainTextAsync("Delete 2 selected");

        await bulkDelete.ClickAsync();
        ILocator dialog = page.Locator("[role=\"dialog\"]");
        await dialog.WaitForAsync();
        await dialog.GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Deleted 2 hotstring");
        await Assertions.Expect(rowA).ToHaveCountAsync(0);
        await Assertions.Expect(rowB).ToHaveCountAsync(0);
    }

    // Backlog 180. The header's select-all checkbox lives in the same column, so a collapsed
    // column would cover it too.
    [Fact]
    public async Task SelectAll_OnDesktopViewport_SelectsEveryRowOnThePage()
    {
        await SeedHotstringsAsync(fixture, ("rowa", "Row A text"), ("rowb", "Row B text"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator rowA = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Row A text" });
        ILocator rowB = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "Row B text" });
        ILocator checkboxA = rowA.Locator("td:first-child input[type=checkbox]");
        ILocator checkboxB = rowB.Locator("td:first-child input[type=checkbox]");
        await rowA.WaitForAsync();
        await rowB.WaitForAsync();

        // Checking the rows start unticked means the ticks below can only come from select-all.
        await Assertions.Expect(checkboxA).Not.ToBeCheckedAsync();
        await Assertions.Expect(checkboxB).Not.ToBeCheckedAsync();

        await page.Locator(".desktop-branch thead th:first-child input[type=checkbox]").CheckAsync();

        await Assertions.Expect(page.Locator(".desktop-branch button.bulk-delete-hotstrings"))
            .ToContainTextAsync("Delete 2 selected");

        // The count proves the page's selection changed. The row ticks prove the owner can see it.
        await Assertions.Expect(checkboxA).ToBeCheckedAsync();
        await Assertions.Expect(checkboxB).ToBeCheckedAsync();
    }

    // Backlog 185. Three 48 px buttons did not fit the 160 px Actions column. In view mode the last
    // one ended 8 px past its cell, and the table container cut it off. In edit mode the third
    // button dropped to a second line. Every state is measured before any assertion runs, so one
    // red run shows each state that fails.
    [Fact]
    public async Task RowButtons_OnDesktopViewport_SitInsideTheActionsCellOnOneLine()
    {
        await SeedHotstringsAsync(fixture, ("btw", "by the way"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator row = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "btw" });
        await row.Locator("button.delete").WaitForAsync();
        ActionsCellLayout view = await MeasureActionsCellAsync(page, row, "button.delete");

        await row.Locator("button.edit").ClickAsync();
        ILocator editRow = page.Locator(".desktop-branch tr.edit-row");
        await editRow.Locator("button.promote-edit").WaitForAsync();
        ActionsCellLayout edit = await MeasureActionsCellAsync(page, editRow, "button.promote-edit");

        // Add stays off while a row is in edit mode.
        await editRow.Locator("button.cancel-edit").ClickAsync();
        await page.Locator(".desktop-branch button.add-hotstring").ClickAsync();
        ILocator draftRow = page.Locator(".desktop-branch tr.draft-row");
        await draftRow.Locator("button.promote-edit").WaitForAsync();
        ActionsCellLayout draft = await MeasureActionsCellAsync(page, draftRow, "button.promote-edit");

        using (new AssertionScope())
        {
            AssertInsideItsCellOnOneLine("view mode", view);
            AssertInsideItsCellOnOneLine("edit mode", edit);
            AssertInsideItsCellOnOneLine("new row", draft);
        }
    }

    private static async Task SeedHotstringsAsync(StackFixture fixture, params (string Trigger, string Replacement)[] hotstrings)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        foreach ((string trigger, string replacement) in hotstrings)
        {
            db.Hotstrings.Add(new HotstringBuilder()
                .WithOwner(TestAuthHandler.TestOwnerOid)
                .WithTrigger(trigger)
                .WithReplacement(replacement)
                .Build());
        }

        await db.SaveChangesAsync();
    }

    private sealed record ActionsCellLayout(LocatorBoundingBoxResult Cell, IReadOnlyList<LocatorBoundingBoxResult> Buttons);

    private static async Task<ActionsCellLayout> MeasureActionsCellAsync(IPage page, ILocator row, string buttonInCell)
    {
        ILocator cell = row.Locator("td").Filter(new() { Has = page.Locator(buttonInCell) });
        LocatorBoundingBoxResult cellBox = await cell.BoundingBoxAsync()
            ?? throw new InvalidOperationException($"The Actions cell that holds {buttonInCell} is not visible.");

        List<LocatorBoundingBoxResult> buttonBoxes = [];
        foreach (ILocator button in await cell.Locator("button").AllAsync())
        {
            buttonBoxes.Add(await button.BoundingBoxAsync()
                ?? throw new InvalidOperationException($"A button in the Actions cell that holds {buttonInCell} is not visible."));
        }

        return new ActionsCellLayout(cellBox, buttonBoxes);
    }

    private static void AssertInsideItsCellOnOneLine(string state, ActionsCellLayout layout)
    {
        layout.Buttons.Should().HaveCount(3, $"{state} shows three row buttons");
        float cellRight = layout.Cell.X + layout.Cell.Width;
        foreach (LocatorBoundingBoxResult button in layout.Buttons)
        {
            button.X.Should().BeGreaterThanOrEqualTo(layout.Cell.X, $"{state}: a button must not start before its cell");
            (button.X + button.Width).Should().BeLessThanOrEqualTo(cellRight, $"{state}: a button must not end past its cell");
            button.Y.Should().BeApproximately(layout.Buttons[0].Y, 0.5f, $"{state}: the row buttons share one line");
        }
    }
}
