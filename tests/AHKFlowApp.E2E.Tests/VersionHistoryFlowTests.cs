using System.Net;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.E2E.Tests.Fixtures;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class VersionHistoryFlowTests(StackFixture fixture) : IAsyncLifetime
{
    public Task InitializeAsync() =>
        fixture.ResetDataAsync();

    public Task DisposeAsync() =>
        Task.CompletedTask;

    [Fact]
    public async Task HotstringHistoryRecycleRestoreAndPurge_DrivesBrowserFlow()
    {
        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("button.add-hotstring");

        await CreateHotstringAsync(page, "vh-hs", "original text");
        Guid hotstringId = await FindHotstringIdAsync("vh-hs");

        await UpdateHotstringReplacementAsync(page, "vh-hs", "first edit");
        await UpdateHotstringReplacementAsync(page, "vh-hs", "second edit");

        await OpenHistoryAsync(page, "vh-hs");
        await page.WaitForSelectorAsync("button.history-version:has-text(\"v2\")");
        await page.WaitForSelectorAsync("button.history-version:has-text(\"v1\")");
        await page.ClickAsync("button.history-version:has-text(\"v1\")");
        await page.WaitForSelectorAsync("text=original text");
        await page.ClickAsync("button.revert-version");
        await page.WaitForSelectorAsync("text=Reverted");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"original text\")");

        await DeleteHotstringAsync(page, "vh-hs");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/recycle-bin");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"vh-hs\")");
        await page.Locator("tbody tr", new() { HasTextString = "vh-hs" })
            .Locator("button.restore-item")
            .ClickAsync();
        await page.WaitForSelectorAsync("text=Hotstring restored.");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"vh-hs\")");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"original text\")");

        await DeleteHotstringAsync(page, "vh-hs");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/recycle-bin");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"vh-hs\")");
        await page.Locator("tbody tr", new() { HasTextString = "vh-hs" })
            .Locator("button.purge-item")
            .ClickAsync();
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.Locator("[role=\"dialog\"]")
            .GetByRole(AriaRole.Button, new() { Name = "Delete forever" })
            .ClickAsync();
        await page.WaitForSelectorAsync("text=Hotstring deleted forever.");
        await page.WaitForSelectorAsync("text=No deleted items.");

        using HttpClient client = fixture.Api.CreateClient();
        HttpResponseMessage historyResponse = await client.GetAsync($"/api/v1/hotstrings/{hotstringId}/history");
        Assert.Equal(HttpStatusCode.NotFound, historyResponse.StatusCode);
    }

    [Fact]
    public async Task HotkeyHistoryAndRecycleRestore_PreservesModifiersAndAction()
    {
        Guid hotkeyId = await SeedHotkeyAsync();

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await ctx.NewPageAsync();

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"Open Terminal\")");

        await UpdateHotkeyAsync(page, "Open Terminal", "F10", "wt first");
        await UpdateHotkeyAsync(page, "Open Terminal", "F11", "wt second");

        await OpenHistoryAsync(page, "Open Terminal");
        await page.WaitForSelectorAsync("button.history-version:has-text(\"v2\")");
        await page.WaitForSelectorAsync("button.history-version:has-text(\"v1\")");
        await page.ClickAsync("button.history-version:has-text(\"v1\")");
        await page.WaitForSelectorAsync("text=Ctrl+Alt+T");
        await page.WaitForSelectorAsync("text=wt.exe");
        await page.ClickAsync("button.revert-version");
        await page.WaitForSelectorAsync("text=Reverted");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"wt.exe\")");

        Hotkey reverted = await FindHotkeyAsync(hotkeyId);
        Assert.True(reverted.Ctrl);
        Assert.True(reverted.Alt);
        Assert.Equal(HotkeyAction.Run, reverted.Action);
        Assert.Equal("T", reverted.Key);
        Assert.Equal("wt.exe", reverted.Parameters);

        await DeleteHotkeyAsync(page, "Open Terminal");

        await page.GotoAsync($"{fixture.Spa.BaseUrl}/recycle-bin");
        await page.WaitForSelectorAsync("tbody tr:has-text(\"Open Terminal\")");
        await page.Locator("tbody tr", new() { HasTextString = "Open Terminal" })
            .Locator("button.restore-item")
            .ClickAsync();
        await page.WaitForSelectorAsync("text=Hotkey restored.");

        Hotkey restored = await FindHotkeyAsync(hotkeyId);
        Assert.True(restored.Ctrl);
        Assert.True(restored.Alt);
        Assert.Equal(HotkeyAction.Run, restored.Action);
        Assert.Equal("T", restored.Key);
        Assert.Equal("wt.exe", restored.Parameters);
    }

    private static async Task CreateHotstringAsync(IPage page, string trigger, string replacement)
    {
        await page.ClickAsync("button.add-hotstring");
        await page.WaitForSelectorAsync("tr.draft-row");
        await page.FillAsync("tr.draft-row input[data-test=\"trigger-input\"]", trigger);
        await page.FillAsync("tr.draft-row input[data-test=\"replacement-input\"]", replacement);
        await page.ClickAsync("tr.draft-row button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring created.");
        await page.WaitForSelectorAsync($"tbody tr:has-text(\"{trigger}\")");
    }

    private static async Task UpdateHotstringReplacementAsync(IPage page, string trigger, string replacement)
    {
        await page.Locator("tbody tr", new() { HasTextString = trigger })
            .Locator("button.start-edit")
            .ClickAsync();
        await page.WaitForSelectorAsync("tr.edit-row");
        await page.FillAsync("tr.edit-row input[data-test=\"replacement-input\"]", replacement);
        await page.ClickAsync("tr.edit-row button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotstring updated.");
        await page.WaitForSelectorAsync($"tbody tr:has-text(\"{replacement}\")");
    }

    private static async Task UpdateHotkeyAsync(IPage page, string description, string key, string parameters)
    {
        await page.Locator("tbody tr", new() { HasTextString = description })
            .Locator("button.start-edit")
            .ClickAsync();
        await page.WaitForSelectorAsync("tr.edit-row");
        await page.FillAsync("tr.edit-row input[data-test=\"key-input\"]", key);
        await page.FillAsync("tr.edit-row input[data-test=\"parameters-input\"]", parameters);
        await page.ClickAsync("tr.edit-row button.commit-edit");
        await page.WaitForSelectorAsync("text=Hotkey updated.");
        await page.WaitForSelectorAsync($"tbody tr:has-text(\"{parameters}\")");
    }

    private static async Task OpenHistoryAsync(IPage page, string rowText)
    {
        await page.Locator("tbody tr", new() { HasTextString = rowText })
            .Locator("button.show-history")
            .ClickAsync();
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
    }

    private static async Task DeleteHotstringAsync(IPage page, string trigger)
    {
        await page.Locator("tbody tr", new() { HasTextString = trigger })
            .Locator("button.delete")
            .ClickAsync();
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.WaitForSelectorAsync("text=You can restore it from the Recycle Bin.");
        await page.Locator("[role=\"dialog\"]")
            .GetByRole(AriaRole.Button, new() { Name = "Delete" })
            .ClickAsync();
        await page.WaitForSelectorAsync("text=Hotstring deleted.");
    }

    private static async Task DeleteHotkeyAsync(IPage page, string description)
    {
        await page.Locator("tbody tr", new() { HasTextString = description })
            .Locator("button.delete")
            .ClickAsync();
        await page.WaitForSelectorAsync("[role=\"dialog\"]");
        await page.WaitForSelectorAsync("text=You can restore it from the Recycle Bin.");
        await page.Locator("[role=\"dialog\"]")
            .GetByRole(AriaRole.Button, new() { Name = "Delete" })
            .ClickAsync();
        await page.WaitForSelectorAsync("text=Hotkey deleted.");
    }

    private async Task<Guid> FindHotstringIdAsync(string trigger)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        return await db.Hotstrings
            .Where(h => h.OwnerOid == TestAuthHandler.TestOwnerOid && h.Trigger == trigger)
            .Select(h => h.Id)
            .SingleAsync();
    }

    private async Task<Guid> SeedHotkeyAsync()
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Hotkey hotkey = new HotkeyBuilder()
            .WithOwner(TestAuthHandler.TestOwnerOid)
            .WithDescription("Open Terminal")
            .WithKey("T")
            .WithCtrl()
            .WithAlt()
            .WithAction(HotkeyAction.Run)
            .WithParameters("wt.exe")
            .Build();

        db.Hotkeys.Add(hotkey);
        await db.SaveChangesAsync();

        return hotkey.Id;
    }

    private async Task<Hotkey> FindHotkeyAsync(Guid id)
    {
        await using AsyncServiceScope scope = fixture.Api.Services.CreateAsyncScope();
        AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        return await db.Hotkeys.SingleAsync(h => h.Id == id);
    }
}
