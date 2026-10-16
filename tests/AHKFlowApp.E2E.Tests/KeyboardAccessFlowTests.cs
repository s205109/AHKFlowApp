using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionB.Name)]
public sealed class KeyboardAccessFlowTests(StackFixtureB fixture) : IAsyncLifetime
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

    // Backlog 168. MudBlazor removes the browser outline and only tints the background by
    // 6 percent on focus. The policy in app.css draws a 2px ring instead, in both themes.
    // The ring colours are MudBlazor 9.3.0's text colour per theme, measured on 2026-10-16.
    [Fact]
    public async Task FocusRing_OnKeyboardFocus_DrawsTheRingInBothThemes()
    {
        await SeedHotstringAsync(fixture, "btw");
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator row = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "btw" });
        await row.WaitForAsync();
        ILocator darkModeToggle = page.Locator("header button.dark-mode-toggle");

        await AssertRingsAsync(page, row, textColour: "rgb(66, 66, 66)");

        // A mouse click is not keyboard focus. The toggle keeps focus, so a missing ring means
        // the policy held, not that focus went somewhere else.
        await darkModeToggle.ClickAsync();
        await Assertions.Expect(darkModeToggle).ToBeFocusedAsync();
        await Assertions.Expect(darkModeToggle).ToHaveCSSAsync("outline-style", "none");

        await AssertRingsAsync(page, row, textColour: "rgba(255, 255, 255, 0.698)");
    }

    // Backlog 168. Each name says what pressing the button will do, so it changes with the state.
    [Fact]
    public async Task AppBarButtons_NameWhatPressingThemDoes()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator drawerToggle = page.Locator("header button.drawer-toggle");
        ILocator darkModeToggle = page.Locator("header button.dark-mode-toggle");

        await Assertions.Expect(drawerToggle).ToHaveAccessibleNameAsync("Close navigation menu");
        await drawerToggle.ClickAsync();
        await Assertions.Expect(drawerToggle).ToHaveAccessibleNameAsync("Open navigation menu");

        await Assertions.Expect(darkModeToggle).ToHaveAccessibleNameAsync("Switch to dark mode");
        await darkModeToggle.ClickAsync();
        await Assertions.Expect(darkModeToggle).ToHaveAccessibleNameAsync("Switch to light mode");
    }

    // Backlog 168. A row's icon buttons name the hotstring they act on.
    [Fact]
    public async Task RowButtons_NameTheirHotstring()
    {
        await SeedHotstringAsync(fixture, "btw");
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator row = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "btw" });
        await row.WaitForAsync();

        await Assertions.Expect(row.Locator("button.edit")).ToHaveAccessibleNameAsync("Edit btw");
        await Assertions.Expect(row.Locator("button.show-history")).ToHaveAccessibleNameAsync("Show history for btw");
        await Assertions.Expect(row.Locator("button.delete")).ToHaveAccessibleNameAsync("Delete btw");
    }

    // Backlog 168. Without a skip link, page content starts at the fourteenth Tab press.
    [Fact]
    public async Task SkipLink_FirstTabStop_MovesFocusIntoThePage()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator add = page.Locator(".desktop-branch button.add-hotstring");
        ILocator skipLink = page.Locator("button.skip-link");
        ILocator mainContent = page.Locator("#main-content");
        await add.WaitForAsync();

        await Assertions.Expect(skipLink).Not.ToBeInViewportAsync();

        await page.Keyboard.PressAsync("Tab");
        await Assertions.Expect(skipLink).ToBeFocusedAsync();
        await Assertions.Expect(skipLink).ToBeInViewportAsync();
        await Assertions.Expect(skipLink).ToHaveAccessibleNameAsync("Skip to main content");

        await page.Keyboard.PressAsync("Enter");
        await Assertions.Expect(mainContent).ToBeFocusedAsync();
        await Assertions.Expect(mainContent).ToHaveCSSAsync("outline-style", "none");

        await page.Keyboard.PressAsync("Tab");
        await Assertions.Expect(add).ToBeFocusedAsync();
    }

    private static async Task AssertRingsAsync(IPage page, ILocator row, string textColour)
    {
        // Real Tab presses prove the nav link is reachable by keyboard. They also put the
        // browser in keyboard mode, so the focus() calls below match :focus-visible.
        ILocator navLink = page.Locator("a.mud-nav-link", new() { HasTextString = "Hotkeys" });
        await TabToAsync(page, navLink);
        await AssertRingAsync(navLink, navLink, textColour, offset: "-2px");

        await AssertRingAsync(page.Locator(".desktop-branch button.add-hotstring"), null, textColour, offset: "2px");
        await AssertRingAsync(row.Locator("button.edit"), null, textColour, offset: "2px");

        // A checkbox hides its input inside a MudBlazor button, so the ring is on that button.
        await AssertRingAsync(row.Locator("td:first-child input[type=checkbox]"),
            row.Locator("td:first-child .mud-button-root"), textColour, offset: "2px");

        // The app bar is green in both themes, so its ring takes the bar's white text colour.
        await AssertRingAsync(page.Locator("header button.drawer-toggle"), null, "rgb(255, 255, 255)", offset: "2px");
    }

    // Focuses `focusTarget` unless it already has focus, proves it matches :focus-visible, then
    // checks the ring on `ringHost`, which defaults to the focus target.
    private static async Task AssertRingAsync(ILocator focusTarget, ILocator? ringHost, string colour, string offset)
    {
        ILocator host = ringHost ?? focusTarget;
        if (!await focusTarget.EvaluateAsync<bool>("el => el === document.activeElement"))
        {
            await Assertions.Expect(host).ToHaveCSSAsync("outline-style", "none");
            await focusTarget.FocusAsync();
        }

        (await focusTarget.EvaluateAsync<bool>("el => el.matches(':focus-visible')"))
            .Should().BeTrue("a ring only shows on keyboard focus");
        await Assertions.Expect(host).ToHaveCSSAsync("outline-style", "solid");
        await Assertions.Expect(host).ToHaveCSSAsync("outline-width", "2px");
        await Assertions.Expect(host).ToHaveCSSAsync("outline-offset", offset);
        await Assertions.Expect(host).ToHaveCSSAsync("outline-color", colour);
    }

    // Presses Tab until `target` has focus. Twenty presses is more than the app bar and the nav
    // menu hold together, so a target that never gets focus fails here.
    private static async Task TabToAsync(IPage page, ILocator target)
    {
        bool reached = false;
        for (int press = 0; press < 20 && !reached; press++)
        {
            await page.Keyboard.PressAsync("Tab");
            reached = await target.EvaluateAsync<bool>("el => el === document.activeElement");
        }

        reached.Should().BeTrue("twenty Tab presses must reach the target");
    }

    private static async Task SeedHotstringAsync(StackFixture fixture, string trigger)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.Hotstrings.Add(new HotstringBuilder()
            .WithOwner(TestAuthHandler.TestOwnerOid)
            .WithTrigger(trigger)
            .WithReplacement("by the way")
            .Build());

        await db.SaveChangesAsync();
    }
}
