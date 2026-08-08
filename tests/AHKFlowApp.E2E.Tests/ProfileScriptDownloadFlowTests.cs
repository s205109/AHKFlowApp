using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class ProfileScriptDownloadFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task DownloadFromProfilesPage_SavesThatProfilesScript()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        // A hotstring gives the generated script something to prove it came from this profile.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");
        await page.ClickAsync("button.add-hotstring");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "dlflow");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", "downloaded from profiles");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.download-profile-script");
        IDownload download = await page.RunAndWaitForDownloadAsync(() =>
            page.ClickAsync("button.download-profile-script"));

        string path = await download.PathAsync()
            ?? throw new InvalidOperationException("Download produced no file path.");
        string script = await File.ReadAllTextAsync(path, System.Text.Encoding.UTF8);

        Assert.Matches(new Regex(@"^\d{8}_\d{6}_ahkflow_.+\.ahk$"), download.SuggestedFilename);
        Assert.Contains("#Requires AutoHotkey v2", script, StringComparison.Ordinal);
        // The option letters belong to the hotstring's own defaults, so the assertion starts at
        // the trigger. What matters here is that the file holds this profile's script.
        Assert.Contains("dlflow::downloaded from profiles", script, StringComparison.Ordinal);
    }

    [Fact]
    public async Task BlockedDownload_ReachableByKeyboard_ShowsWhyItRefuses()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.start-edit");

        // Editing a row blocks its download: the server builds the script from saved data.
        await page.ClickAsync("button.start-edit");

        ILocator download = page.Locator("button.download-profile-script").First;
        await Assertions.Expect(download).ToHaveAttributeAsync("aria-disabled", "true");

        // The HTML attribute is what removes a button from the tab order, so that is what this
        // asserts. Playwright's ToBeDisabled counts aria-disabled as disabled too, so it cannot
        // tell the two mechanisms apart, and Not.ToBeDisabled would never pass on this button.
        bool reallyDisabled = await download.EvaluateAsync<bool>("el => el.hasAttribute('disabled')");
        Assert.False(reallyDisabled, "The blocked button must not carry the disabled attribute.");

        // Nothing is open yet. Without this the next assertion could pass on a popover that was
        // already showing.
        await Assertions.Expect(page.Locator(".mud-popover-open.blocked-action-text"))
            .ToHaveCountAsync(0);

        // The sighted keyboard path. Tab is pressed for real, because FocusAsync would prove only
        // that the element can hold focus, not that keyboard navigation ever reaches it.
        bool reached = false;
        for (int i = 0; i < 60 && !reached; i++)
        {
            await page.Keyboard.PressAsync("Tab");
            reached = await download.EvaluateAsync<bool>("el => el === document.activeElement");
        }

        Assert.True(reached, "Tab never reached the blocked download button, so it left the tab order.");

        await Assertions.Expect(page.Locator(".mud-popover-open.blocked-action-text"))
            .ToContainTextAsync("Save your changes first");

        // The activation path, shared by Enter, Space, a mouse click, and a tap.
        await page.Keyboard.PressAsync("Enter");
        await Assertions.Expect(page.Locator(".mud-snackbar")).ToContainTextAsync("Save your changes first");
    }
}
