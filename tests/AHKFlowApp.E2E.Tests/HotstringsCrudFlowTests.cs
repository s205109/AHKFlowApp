using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

public sealed class HotstringsCrudFlowTests(StackFixture fixture) : IClassFixture<StackFixture>
{
    [Fact]
    public async Task CreateEditDelete_DrivesBlazorSpaThroughBrowser()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("td.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "btw");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "by the way");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");

        IReadOnlyList<IElementHandle> rows = await page.QuerySelectorAllAsync("tbody tr");
        Assert.True(rows.Count >= 1);
        Assert.True(await page.IsVisibleAsync("text=by the way"));

        await page.ClickAsync("button.start-edit");
        await page.WaitForSelectorAsync("td.edit-row");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "by the way!");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring updated.");
        Assert.True(await page.IsVisibleAsync("text=by the way!"));

        await page.ClickAsync("button.delete");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.GetByRole(AriaRole.Button, new() { Name = "Delete" }).Last.ClickAsync();

        await page.WaitForSelectorAsync("text=Hotstring deleted.");
        await page.WaitForSelectorAsync("text=No hotstrings yet.");
    }

    [Fact]
    public async Task DuplicateTrigger_ShowsConflictSnackbar()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("td.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "dup");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "duplicate");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");

        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("td.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "dup");
        await page.FillAsync("input[data-test=\"replacement-input\"]", "duplicate again");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=/already exists/i");
    }
}
