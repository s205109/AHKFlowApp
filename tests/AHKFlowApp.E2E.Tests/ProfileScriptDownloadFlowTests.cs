using System.IO.Compression;
using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionD.Name)]
public sealed class ProfileScriptDownloadFlowTests(StackFixtureD fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task DownloadFromProfilesPage_SavesThatProfilesScript()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        // A hotstring gives the generated script something to prove it came from this profile.
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
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

        // Backlog 183. The browser saves the API's bytes unchanged: the mark, then LF only. The
        // seeded profile's header is the CRLF default, so this fails without the fix.
        byte[] bytes = await File.ReadAllBytesAsync(path);
        Assert.Equal(new byte[] { 0xEF, 0xBB, 0xBF }, bytes[..3]);
        Assert.DoesNotContain((byte)'\r', bytes);
    }

    [Fact]
    public async Task SingleDownload_SavesUnderTheNameTheApiSends()
    {
        // Backlog 171. The route answers every single download with a file name that no seeded
        // profile produces. So the saved name can only come from the API's Content-Disposition
        // header, never from a profile name the UI turned into a stem itself.
        const string apiName = "ahkflow_Named_By_The_Route.ahk";

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        await ctx.RouteAsync("**/api/v1/downloads/*", route => route.FulfillAsync(new RouteFulfillOptions
        {
            Status = 200,
            ContentType = "text/plain; charset=utf-8",
            Headers = new Dictionary<string, string>
            {
                ["Content-Disposition"] = $"attachment; filename={apiName}",
            },
            Body = "; served by the test route",
        }));

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");
        IDownload download = await page.RunAndWaitForDownloadAsync(() =>
            page.Locator("button.download-profile").First.ClickAsync());

        AssertStampedApiName(apiName, download);
    }

    [Fact]
    public async Task LongName_SingleDownloadAndZip_UseOneStem()
    {
        // Backlog 171. 63 letters, a space, then 'bbb'. The stem's 64th character is the
        // underscore, which is where the API and the UI used to disagree.
        string profileName = new string('a', 63) + " bbb";
        string apiName = "ahkflow_" + new string('a', 63) + ".ahk";

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.add-profile");
        await page.ClickAsync("button.add-profile");
        await page.FillAsync("input[data-test=\"profile-name-input\"]", profileName);
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Profile created.");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");
        // Scope the click to the new profile's row. The seeded profiles have their own rows.
        ILocator row = page.Locator("tr").Filter(new() { HasTextString = profileName }).First;
        IDownload single = await page.RunAndWaitForDownloadAsync(() =>
            row.Locator("button.download-profile").ClickAsync());

        IDownload zipDownload = await page.RunAndWaitForDownloadAsync(() =>
            page.ClickAsync("button.download-all"));
        string zipPath = await zipDownload.PathAsync()
            ?? throw new InvalidOperationException("The zip download produced no file path.");
        await using FileStream stream = File.OpenRead(zipPath);
        using ZipArchive zip = new(stream, ZipArchiveMode.Read);

        AssertStampedApiName(apiName, single);
        string[] entries = [.. zip.Entries.Select(e => e.Name)];
        Assert.True(entries.Contains(apiName), $"The zip holds {string.Join(", ", entries)}, not {apiName}.");
    }

    // The saved name is the 15-character stamp, an underscore, then the API's name.
    private static void AssertStampedApiName(string apiName, IDownload download)
    {
        Assert.Matches(new Regex(@"^\d{8}_\d{6}_"), download.SuggestedFilename);
        Assert.Equal(apiName, download.SuggestedFilename[16..]);
    }

    [Fact]
    public async Task BlockedDownload_ReachableByKeyboard_ShowsWhyItRefuses()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/profiles");
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
