using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.E2E.Tests.Fixtures;
using Microsoft.Playwright;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ECollectionB.Name)]
public sealed class ProfileDeleteFlowTests(StackFixtureB fixture) : IAsyncLifetime
{
    public Task InitializeAsync() => fixture.ResetDataAsync();

    public Task DisposeAsync() => Task.CompletedTask;

    // Backlog 210: a profile delete silently left items applying to no profile, and nothing
    // marked them afterwards.
    [Fact]
    public async Task DeleteProfile_NamesTheCost_ThenMarksTheItemAfterAReload()
    {
        // The hotkey is in the seed so the flow proves the client reads both count fields from
        // the JSON. The page tests stub the client, so they cannot show that.
        using HttpClient client = fixture.Api.CreateClient();
        ProfileDto work = await PostAsync<ProfileDto>(client, "/api/v1/profiles", new CreateProfileDto("Work"));
        (await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto(
            "orphan", "left behind", ProfileIds: [work.Id], AppliesToAllProfiles: false))).EnsureSuccessStatusCode();
        (await client.PostAsJsonAsync("/api/v1/hotkeys", new CreateHotkeyDto(
            "Left behind", "f16", HotkeyActionKind.Disable, ProfileIds: [work.Id]))).EnsureSuccessStatusCode();

        await using IBrowserContext ctx = await fixture.Browser.NewContextAsync();
        IPage page = await FirstPageLoad.OpenAsync(ctx, $"{fixture.Spa.BaseUrl}/profiles");

        await page.ClickAsync("button[aria-label=\"Delete Work\"]");

        ILocator dialog = page.Locator("[role=\"dialog\"]");
        await Assertions.Expect(dialog)
            .ToContainTextAsync("1 hotstring and 1 hotkey apply only to this profile.");
        // Scoped to the dialog: the row's own button is named "Delete Work", which also matches.
        await dialog.GetByRole(AriaRole.Button, new() { Name = "Delete" }).ClickAsync();

        await Assertions.Expect(page.Locator(".mud-snackbar"))
            .ToContainTextAsync("Profile deleted. 1 hotstring and 1 hotkey now apply to no profile.");

        // A fresh navigation is the reload: the grid reads stored state, nothing from the delete.
        await page.GotoAsync($"{fixture.Spa.BaseUrl}/hotstrings");
        await Assertions.Expect(page.Locator("tbody tr:has-text(\"orphan\") .no-profile-chip"))
            .ToHaveTextAsync("No profile");
    }

    private static async Task<T> PostAsync<T>(HttpClient client, string url, object body)
    {
        HttpResponseMessage response = await client.PostAsJsonAsync(url, body);
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<T>())!;
    }
}
