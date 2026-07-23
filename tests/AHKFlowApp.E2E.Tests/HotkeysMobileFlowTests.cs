using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class HotkeysMobileFlowTests(StackFixture fixture) : IAsyncLifetime
{
    private static readonly BrowserNewContextOptions PhoneViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 375, Height = 812 },
    };

    private static readonly BrowserNewContextOptions TabletViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 768, Height = 1024 },
    };

    private sealed class OverflowMetrics
    {
        public int BodyOverflow { get; init; }

        public int DocumentOverflow { get; init; }
    }

    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task TabletViewport_DoesNotCreatePageHorizontalOverflow()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(TabletViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey-fab");

        OverflowMetrics metrics = await page.EvaluateAsync<OverflowMetrics>(
            "() => ({ BodyOverflow: document.body.scrollWidth - window.innerWidth, DocumentOverflow: document.documentElement.scrollWidth - window.innerWidth })");

        Assert.True(metrics.BodyOverflow <= 0, $"Body overflowed by {metrics.BodyOverflow}px.");
        Assert.True(metrics.DocumentOverflow <= 0, $"Document overflowed by {metrics.DocumentOverflow}px.");
    }

    [Fact]
    public async Task AddFab_OnPhoneViewport_OpensHotkeyDialog()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        Task<IResponse> profilesLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/profiles", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);
        Task<IResponse> categoriesLoaded = page.WaitForResponseAsync(response =>
            response.Url.Contains("/api/v1/categories", StringComparison.OrdinalIgnoreCase) &&
            response.Status == 200);

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("button.add-hotkey-fab");
        await Task.WhenAll(profilesLoaded, categoriesLoaded);

        await page.ClickAsync("button.add-hotkey-fab");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog");
        await page.WaitForSelectorAsync(".hotkey-edit-dialog input[data-test=\"description-input\"]");
        // The dialog's key field is the KeyPicker autocomplete (key-picker); key-input is the
        // desktop grid's inline editor and no longer exists in the dialog.
        await page.WaitForSelectorAsync(".hotkey-edit-dialog input[data-test=\"key-picker\"]");
    }

    [Fact]
    public async Task ExpandedRow_OnPhoneViewport_ShowsActionChipAndSummary()
    {
        await SeedRunHotkeyAsync(fixture, "Launch Terminal", "F5", "wt.exe");

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        ILocator row = page.Locator(".mobile-row", new() { HasTextString = "Launch Terminal" });
        await row.WaitForAsync();

        // Tapping the row expands it; the expanded panel renders the typed action's chip and
        // one-line summary — the rows replacing the old free-text Action/Parameters cells.
        await row.ClickAsync();

        ILocator expanded = page.Locator(".mobile-row-expanded");
        await expanded.WaitForAsync();
        (await expanded.Locator("[data-test=\"action-chip\"]").InnerTextAsync()).Should().Contain("Run");
        await Assertions.Expect(expanded).ToContainTextAsync("wt.exe");
    }

    [Fact]
    public async Task BulkDelete_OnPhoneViewport_UsesSelectMode()
    {
        await SeedHotkeysAsync(fixture, ("Macro A", "F1"), ("Macro B", "F2"));

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(PhoneViewport);
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"F1\")");
        await page.WaitForSelectorAsync(".mobile-row:has-text(\"F2\")");

        // Enter select mode + select both
        await page.ClickAsync("button.toggle-select-mode");
        await page.WaitForSelectorAsync("input.row-checkbox");
        foreach (string key in new[] { "F1", "F2" })
            await page.Locator($"xpath=//tr[contains(@class,'mobile-row')][.//code[normalize-space(.)='{key}']]//input[contains(@class,'row-checkbox')]").CheckAsync();

        await page.ClickAsync("button.bulk-delete-hotkeys");
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.Locator("[role=\"dialog\"]").GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await page.WaitForSelectorAsync("text=Deleted 2 hotkey");
    }

    private static async Task SeedHotkeysAsync(StackFixture fixture, params (string Description, string Key)[] hotkeys)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        foreach ((string description, string key) in hotkeys)
        {
            db.Hotkeys.Add(new HotkeyBuilder()
                .WithOwner(TestAuthHandler.TestOwnerOid)
                .WithDescription(description)
                .WithKey(key)
                .Build());
        }

        await db.SaveChangesAsync();
    }

    private static async Task SeedRunHotkeyAsync(StackFixture fixture, string description, string key, string target)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        db.Hotkeys.Add(new HotkeyBuilder()
            .WithOwner(TestAuthHandler.TestOwnerOid)
            .WithDescription(description)
            .WithKey(key)
            .WithRun(target)
            .Build());

        await db.SaveChangesAsync();
    }
}
