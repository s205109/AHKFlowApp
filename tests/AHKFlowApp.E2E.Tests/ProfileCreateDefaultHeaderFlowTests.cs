using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionA.Name)]
public sealed class ProfileCreateDefaultHeaderFlowTests(StackFixtureA fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    [Fact]
    public async Task CreateProfile_WithoutTouchingTheHeader_GeneratesAScriptWithTheDirectives()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.add-profile");

        await page.ClickAsync("button.add-profile");
        await page.WaitForSelectorAsync("textarea[data-test=\"profile-header-input\"]");

        // The owner sees the default header before they save it. That is the point of the fix:
        // the text is theirs to read and change, not something the server adds behind them.
        string headerInTheForm =
            await page.InputValueAsync("textarea[data-test=\"profile-header-input\"]");
        Assert.Contains("#Requires AutoHotkey v2.0", headerInTheForm);
        Assert.Contains("#SingleInstance Force", headerInTheForm);

        await page.FillAsync("input[data-test=\"profile-name-input\"]", "Gaming");
        await page.ClickAsync("button.commit-edit");
        await page.WaitForSelectorAsync("text=Profile created.");

        // Scope every later click to the new profile's own row. The seeded Default profile sorts
        // first, so an unscoped selector would drive the wrong row.
        ILocator row = page.Locator("tr").Filter(new() { HasTextString = "Gaming" }).First;

        await row.Locator("button.toggle-expand").ClickAsync();
        await page.ClickAsync("text=Script preview");
        await page.ClickAsync("button.profile-preview-refresh");
        await page.WaitForSelectorAsync("pre.profile-preview-script");

        string script = await page.InnerTextAsync("pre.profile-preview-script");
        Assert.Contains("#Requires AutoHotkey v2.0", script);
        Assert.Contains("#SingleInstance Force", script);
        Assert.Contains("SendMode \"Input\"", script);
        Assert.Contains("SetTitleMatchMode 2", script);
    }

    [Fact]
    public async Task InsertPresetIntoANewProfile_KeepsTheDirectivesAboveThePreset()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();

        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/profiles");
        await page.WaitForSelectorAsync("button.add-profile");

        await page.ClickAsync("button.add-profile");
        await page.WaitForSelectorAsync("textarea[data-test=\"profile-header-input\"]");

        await page.ClickAsync("button.header-preset-open");
        await page.ClickAsync("button[data-test=\"header-preset-insert-lock-keys-off\"]");
        await page.WaitForSelectorAsync("text=Preset added to the header.");

        string headerInTheForm =
            await page.InputValueAsync("textarea[data-test=\"profile-header-input\"]");
        Assert.Contains("#Requires AutoHotkey v2.0", headerInTheForm);
        Assert.Contains("; --- AHKFlow preset: lock-keys-off ---", headerInTheForm);
        Assert.True(
            headerInTheForm.IndexOf("#Requires AutoHotkey v2.0", StringComparison.Ordinal)
                < headerInTheForm.IndexOf("; --- AHKFlow preset:", StringComparison.Ordinal),
            "The directives must stay above the preset the owner inserted.");
    }
}
