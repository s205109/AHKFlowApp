using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class ProfileHeaderPresetFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task InsertPreset_AppendsMarkedBlockAndThenReportsItAsPresent()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.start-edit");

        // Insert a preset into the default profile's header.
        await page.ClickAsync("button.start-edit");
        await page.WaitForSelectorAsync("textarea[data-test=\"profile-header-input\"]");
        await page.ClickAsync("button.header-preset-open");
        await page.ClickAsync("button[data-test=\"header-preset-insert-lock-keys-off\"]");

        await page.WaitForSelectorAsync("text=Preset added to the header.");
        string headerAfterInsert =
            await page.InputValueAsync("textarea[data-test=\"profile-header-input\"]");
        Assert.Contains("; --- AHKFlow preset: lock-keys-off ---", headerAfterInsert);
        Assert.Contains("; --- end lock-keys-off ---", headerAfterInsert);

        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Profile updated.");

        // Re-open the editor: the preset is now reported as present.
        await page.ClickAsync("button.start-edit");
        await page.WaitForSelectorAsync("textarea[data-test=\"profile-header-input\"]");
        await page.ClickAsync("button.header-preset-open");

        await page.WaitForSelectorAsync("text=Already in the header");
        Assert.Empty(await page.QuerySelectorAllAsync(
            "button[data-test=\"header-preset-insert-lock-keys-off\"]"));

        await page.ClickAsync("button.cancel-preset-picker");
        await page.ClickAsync("button.cancel-edit");

        // The block reaches the generated script, not only the stored header.
        await page.ClickAsync("button.toggle-expand");
        await page.ClickAsync("text=Script preview");
        await page.ClickAsync("button.profile-preview-refresh");
        await page.WaitForSelectorAsync("pre.profile-preview-script");

        string script = await page.InnerTextAsync("pre.profile-preview-script");
        Assert.Contains("; --- AHKFlow preset: lock-keys-off ---", script);
        Assert.Contains("SetScrollLockState \"AlwaysOff\"", script);
        Assert.Contains("; --- end lock-keys-off ---", script);
    }
}
