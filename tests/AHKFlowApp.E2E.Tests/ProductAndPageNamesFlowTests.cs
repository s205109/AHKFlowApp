// Backlog 170. Every place the product name shows must read AHKFlowApp,
// and each page keeps one name for its nav link, its browser tab and its heading.
using System.Text.Json;
using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionB.Name)]
public sealed class ProductAndPageNamesFlowTests(StackFixtureB fixture)
{
    private const string ProductName = "AHKFlowApp";

    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    private sealed class HeadingMetrics
    {
        public int ScrollWidth { get; init; }

        public int ClientWidth { get; init; }

        public double Left { get; init; }

        public double Right { get; init; }

        public int ViewportWidth { get; init; }
    }

    [Fact]
    public async Task HomePage_SpellsTheProductOneWay()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/");

        await Assertions.Expect(page).ToHaveTitleAsync(ProductName);
        await Assertions.Expect(page.Locator("[data-test=\"app-title\"]")).ToHaveTextAsync(ProductName);
        await Assertions.Expect(page.Locator("[data-test=\"hero-heading\"]")).ToHaveTextAsync($"Welcome to {ProductName}");
    }

    [Fact]
    public async Task StaticFiles_SpellTheProductOneWay()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/");

        string index = await page.EvaluateAsync<string>(
            "url => fetch(url).then(response => response.text())",
            $"{fixture.Spa.BaseUrl}/index.html");
        string manifestJson = await page.EvaluateAsync<string>(
            "url => fetch(url).then(response => response.text())",
            $"{fixture.Spa.BaseUrl}/manifest.webmanifest");

        string indexTitle = Regex.Match(index, "<title>([^<]*)</title>").Groups[1].Value;
        using var manifest = JsonDocument.Parse(manifestJson);
        string name = manifest.RootElement.GetProperty("name").GetString()!;
        string shortName = manifest.RootElement.GetProperty("short_name").GetString()!;
        string description = manifest.RootElement.GetProperty("description").GetString()!;

        Assert.Equal(ProductName, indexTitle);
        Assert.Equal("AHKFlowApp — AutoHotkey Hotstring Manager", name);
        Assert.Equal(ProductName, shortName);
        Assert.True(shortName.Length < name.Length, $"short_name '{shortName}' must be shorter than name '{name}'.");
        Assert.Equal("Manage your AutoHotkey hotstrings and hotkeys in one place.", description);
    }

    [Fact]
    public async Task HeroHeading_OnPhoneViewport_FitsItsWidth()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/");

        ILocator heading = page.Locator("[data-test=\"hero-heading\"]");
        await heading.WaitForAsync();

        HeadingMetrics metrics = await heading.EvaluateAsync<HeadingMetrics>(
            """
            async el => {
                await document.fonts.ready;
                const box = el.getBoundingClientRect();
                return {
                    ScrollWidth: el.scrollWidth,
                    ClientWidth: el.clientWidth,
                    Left: box.left,
                    Right: box.right,
                    ViewportWidth: window.innerWidth
                };
            }
            """);

        Assert.True(
            metrics.ScrollWidth <= metrics.ClientWidth,
            $"The hero heading's text is wider than its box (scrollWidth {metrics.ScrollWidth}, clientWidth {metrics.ClientWidth}).");
        Assert.True(
            metrics.Left >= 0 && metrics.Right <= metrics.ViewportWidth,
            $"The hero heading's box runs past a {metrics.ViewportWidth} px screen (left {metrics.Left}, right {metrics.Right}).");
    }
}
