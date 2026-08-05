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
}
