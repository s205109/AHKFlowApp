using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionB.Name)]
public sealed class NoProfileNoticeFlowTests(StackFixtureB fixture) : IAsyncLifetime
{
    // Well above the 959.95 px breakpoint, so the page shows the desktop grid.
    private static readonly BrowserNewContextOptions DesktopViewport = new()
    {
        ViewportSize = new ViewportSize { Width = 1280, Height = 800 },
    };

    private const string NoticeStart = "This item applies to no profile, so no script contains it.";

    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    // Backlog 211: an item with no profile opened in either edit dialog with no reason given.
    [Fact]
    public async Task EditDialogs_ItemWithNoProfile_ShowTheNoticeUntilTheOwnerScopesIt()
    {
        // A profile delete is how an item really ends up with no profile.
        using HttpClient client = fixture.Api.CreateClient();
        ProfileDto work = await PostAsync<CreateProfileDto, ProfileDto>(
            client, "/api/v1/profiles", new CreateProfileDto("Work"));
        await PostAsync<CreateProfileDto, ProfileDto>(client, "/api/v1/profiles", new CreateProfileDto("Home"));
        await PostAsync<CreateHotstringDto, HotstringDto>(client, "/api/v1/hotstrings",
            new CreateHotstringDto("orphan", "left behind", ProfileIds: [work.Id], AppliesToAllProfiles: false));
        await PostAsync<CreateHotkeyDto, HotkeyDto>(client, "/api/v1/hotkeys",
            new CreateHotkeyDto("Left behind", "F16", HotkeyActionKind.Disable, ProfileIds: [work.Id]));
        (await client.DeleteAsync($"/api/v1/profiles/{work.Id}")).EnsureSuccessStatusCode();

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync(DesktopViewport);

        // Hotstrings. A Text row edits inline, and its promote button opens the dialog with a clone
        // of the row. So this path also proves that Clone keeps the flag.
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/hotstrings");
        ILocator row = page.Locator(".desktop-branch tbody tr", new() { HasTextString = "orphan" });
        await row.Locator("button.edit").ClickAsync();
        await page.Locator(".desktop-branch tr.edit-row button.promote-edit").ClickAsync();

        ILocator hotstringNotice = page.Locator(".hotstring-edit-dialog [data-test=\"no-profile-notice\"]");
        await Assertions.Expect(hotstringNotice).ToContainTextAsync(NoticeStart);
        await ChooseProfileAsync(page, ".hotstring-edit-dialog", "Home");
        await Assertions.Expect(hotstringNotice).ToHaveCountAsync(0);

        // Hotkeys. A Disable row is not inline editable, so its Edit button opens the dialog.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotkeys");
        await page.ClickAsync("button[aria-label=\"Edit Left behind\"]");

        ILocator hotkeyNotice = page.Locator(".hotkey-edit-dialog [data-test=\"no-profile-notice\"]");
        await Assertions.Expect(hotkeyNotice).ToContainTextAsync(NoticeStart);
        await page.CheckAsync(".hotkey-edit-dialog input[data-test=\"applies-to-all-checkbox\"]");
        await Assertions.Expect(hotkeyNotice).ToHaveCountAsync(0);
    }

    private static async Task<TResult> PostAsync<TBody, TResult>(HttpClient client, string path, TBody body)
    {
        HttpResponseMessage response = await client.PostAsJsonAsync(path, body);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<TResult>())!;
    }

    // MudSelect can miss a click while its popover is still animating in. This is a multi-select,
    // so its popover stays open after a choice, and a second click on the option would clear it
    // again. So the loop clicks again only when the value never landed.
    private static async Task ChooseProfileAsync(IPage page, string dialog, string name)
    {
        ILocator select = page.Locator($"{dialog} input[data-test=\"profile-select\"]");
        ILocator option = page.Locator($".mud-popover-open .mud-list-item:has-text(\"{name}\")");

        for (int attempt = 0; attempt < 5; attempt++)
        {
            if (!await option.IsVisibleAsync())
                await select.ClickAsync();
            await option.WaitForAsync(new() { State = WaitForSelectorState.Visible });
            await option.ClickAsync();

            try
            {
                await Assertions.Expect(select).ToHaveValueAsync(name, new() { Timeout = 2_000 });
                return;
            }
            catch (PlaywrightException)
            {
                // The click missed. Try again.
            }
        }

        (await select.InputValueAsync()).Should().Be(name, "the profile choice must commit");
    }
}
