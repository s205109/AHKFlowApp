using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

// Guards the local no-auth (test provider) mode agent worktrees and the "No Auth" launch profiles
// rely on: the app boots already signed in as the synthetic user and full CRUD works with no login.
[Collection(E2ETestCollection.Name)]
public sealed class LocalAuthModeFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task LocalInstallMode_SignsInSyntheticUserAndAllowsCrud()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        // Local-install-mode signature (Shared/LoginDisplay.razor): a *disabled* Log out button only
        // renders in the Authorized + test-auth branch, so it proves both "signed in" and no-auth mode.
        // The app bar sits behind an async AuthorizeView, so wait for it rather than snapshotting.
        ILocator logOut = page.Locator("button:has-text(\"Log out\")");
        await logOut.WaitForAsync();
        Assert.True(await logOut.IsDisabledAsync());

        // Full CRUD works without any login step.
        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("tr.draft-row");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "btw");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", "by the way");
        await page.ClickAsync("button.commit-edit");

        await page.WaitForSelectorAsync("text=Hotstring created.");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"btw\")");
    }
}
