using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class ClipboardDeliveryFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task AutoLongText_DownloadedScriptContainsOneHelperAndPasteCall()
    {
        await using IBrowserContext context = await fixture.Browser.NewContextAsync();
        IPage page = await context.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.add-profile");
        await page.ClickAsync("button.add-profile");
        await page.FillAsync("input[data-test=\"profile-name-input\"]", "ClipboardFlow");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=ClipboardFlow");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");
        await page.ClickAsync("button.add-hotstring");
        await page.FillAsync("input[data-test=\"trigger-input\"]", "longclip");
        await page.FillAsync("textarea[data-test=\"replacement-input\"]", new string('x', 250));
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/downloads");
        await page.WaitForSelectorAsync("button.download-profile");
        IDownload download = await page.RunAndWaitForDownloadAsync(() =>
            page.ClickAsync("button.download-profile"));

        string path = await download.PathAsync()
            ?? throw new InvalidOperationException("Download produced no file path.");
        string script = await File.ReadAllTextAsync(path, System.Text.Encoding.UTF8);

        Assert.Equal(1, CountOccurrences(script, "AhkFlow_PasteReplacement(text, endChar := \"\")"));
        Assert.Contains("AhkFlow_PasteReplacement(", script, StringComparison.Ordinal);
        Assert.Contains(":X?:longclip::AhkFlow_PasteReplacement(", script, StringComparison.Ordinal);
    }

    private static int CountOccurrences(string value, string search)
    {
        int count = 0;
        int index = 0;
        while ((index = value.IndexOf(search, index, StringComparison.Ordinal)) >= 0)
        {
            count++;
            index += search.Length;
        }
        return count;
    }
}
