using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotkeys;

[Collection("WebApi")]
public sealed class HotkeyKeysEndpointTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    [Fact]
    public async Task GetKeys_ReturnsRegistryWithRolesAndAliases()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys/keys");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyKeyCatalogDto? catalog = await response.Content.ReadFromJsonAsync<HotkeyKeyCatalogDto>();
        catalog.Should().NotBeNull();
        catalog!.Keys.Should().NotBeEmpty();
        catalog.Aliases.Should().ContainKey("Esc").WhoseValue.Should().Be("Escape");
    }

    [Fact]
    public async Task GetKeys_NamedKeyCarriesBraceFlagAndSendRole()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        HotkeyKeyCatalogDto? catalog =
            await client.GetFromJsonAsync<HotkeyKeyCatalogDto>("/api/v1/hotkeys/keys");

        HotkeyKeyDto volumeUp = catalog!.Keys.Single(k => k.Canonical == "Volume_Up");
        volumeUp.RequiresBracesInSend.Should().BeTrue();
        volumeUp.Roles.Should().Contain("SendToken");
        volumeUp.Group.Should().Be("Media & browser");
    }

    [Fact]
    public async Task GetKeys_PrintableKeyIsNotBracedInSend()
    {
        HttpClient client = _factory.CreateAuthenticatedClient();

        HotkeyKeyCatalogDto? catalog =
            await client.GetFromJsonAsync<HotkeyKeyCatalogDto>("/api/v1/hotkeys/keys");

        catalog!.Keys.Single(k => k.Canonical == "c").RequiresBracesInSend.Should().BeFalse();
    }

    [Fact]
    public async Task GetKeys_RequiresAuthentication()
    {
        HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys/keys");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
