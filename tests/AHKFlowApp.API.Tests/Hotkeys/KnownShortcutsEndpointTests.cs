using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotkeys;

[Collection("WebApi")]
public sealed class KnownShortcutsEndpointTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task GetKnownShortcuts_ReturnsTheCatalog()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys/known-shortcuts");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        KnownShortcutCatalogDto? catalog =
            await response.Content.ReadFromJsonAsync<KnownShortcutCatalogDto>();
        catalog.Should().NotBeNull();
        // No count here. KnownShortcutCatalog is internal to AHKFlowApp.Application, and that
        // project's InternalsVisibleTo names only Application.Tests and TestUtilities — reading
        // All.Count from this project would not compile. The exact count is asserted once, in
        // Application.Tests' All_HasExpectedRecordCount. This suite owns the HTTP contract instead.
        catalog!.Shortcuts.Should().NotBeEmpty();
    }

    [Fact]
    public async Task GetKnownShortcuts_WindowsRowCarriesGlobalScopeAndDoesPhrase()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        KnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<KnownShortcutCatalogDto>("/api/v1/hotkeys/known-shortcuts");

        KnownShortcutDto explorer = catalog!.Shortcuts.Single(s => s.Id == "windows.file-explorer");
        // Lowercase because that is the canonical spelling HotkeyKeys gives letter keys.
        explorer.Key.Should().Be("e");
        explorer.Win.Should().BeTrue();
        explorer.Ctrl.Should().BeFalse();

        ShortcutUseDto use = explorer.Uses.Single();
        use.UsedBy.Should().Be("Windows");
        use.Scope.Should().Be(ShortcutScope.Global);
        use.Protection.Should().Be(ShortcutProtection.Normal);
        use.Does.Should().Be("open File Explorer");
    }

    [Fact]
    public async Task GetKnownShortcuts_BrowserRowCarriesTwoForegroundUses()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        KnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<KnownShortcutCatalogDto>("/api/v1/hotkeys/known-shortcuts");

        KnownShortcutDto newWindow = catalog!.Shortcuts.Single(s => s.Id == "browser.new-window");
        newWindow.Key.Should().Be("n");
        newWindow.Ctrl.Should().BeTrue();
        newWindow.Win.Should().BeFalse();

        newWindow.Uses.Select(u => u.UsedBy).Should().BeEquivalentTo(["Chrome", "Edge"]);
        newWindow.Uses.Should().OnlyContain(u => u.Scope == ShortcutScope.Foreground);
        newWindow.Uses.Should().OnlyContain(u => u.Does == "open a new window");
    }

    [Fact]
    public async Task GetKnownShortcuts_ProtectedRowIsMarkedProtected()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        KnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<KnownShortcutCatalogDto>("/api/v1/hotkeys/known-shortcuts");

        catalog!.Shortcuts.Single(s => s.Id == "windows.lock")
            .Uses.Single().Protection.Should().Be(ShortcutProtection.Protected);
    }

    [Fact]
    public async Task GetKnownShortcuts_DoesNotLeakCurationMetadata()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        string json = await client.GetStringAsync("/api/v1/hotkeys/known-shortcuts");

        json.Should().NotContain("evidence", "curation metadata stays server-side");
    }

    [Fact]
    public async Task GetKnownShortcuts_WithoutAuth_IsRefused()
    {
        HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys/known-shortcuts");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
