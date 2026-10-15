using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionB.Name)]
public sealed class DashboardFirstViewFlowTests(StackFixtureB fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task FirstViewOfTheDashboard_CountsTheDefaultProfile()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        // The reset deleted every profile, and the dashboard is the first page this owner opens.
        // So no request to /api/v1/profiles has created the Default profile yet.
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/", "/api/v1/dashboard/stats");

        ILocator card = page.Locator("[data-test=\"stat-card-profiles\"]");
        await Assertions.Expect(card.Locator("[data-test=\"stat-card-total\"]")).ToHaveTextAsync("1");
        await Assertions.Expect(card.Locator("[data-test=\"stat-card-footer\"]")).ToHaveTextAsync("+1 this week");
    }
}
