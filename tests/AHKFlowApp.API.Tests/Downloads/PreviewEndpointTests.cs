using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Downloads;

[Collection("WebApi")]
public sealed class PreviewEndpointTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    private static async Task<ProfileDto> CreateProfileAsync(HttpClient client, string name)
    {
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto(name, null, null));
        created.EnsureSuccessStatusCode();
        return (await created.Content.ReadFromJsonAsync<ProfileDto>())!;
    }

    [Fact]
    public async Task GET_preview_returns_json_payload()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Work");

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{profile.Id}/preview");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/json");
        ProfileScriptPreviewDto dto = (await response.Content.ReadFromJsonAsync<ProfileScriptPreviewDto>())!;
        dto.Script.Should().Contain("#Requires AutoHotkey v2.0");
        dto.HotstringCount.Should().Be(0);
        dto.HotkeyCount.Should().Be(0);
        dto.GeneratedAt.Should().BeAfter(DateTimeOffset.UtcNow.AddMinutes(-1));
    }

    [Fact]
    public async Task GET_preview_script_matches_download_body()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Work");

        string downloadBody = await client.GetStringAsync($"/api/v1/downloads/{profile.Id}");
        ProfileScriptPreviewDto preview =
            (await client.GetFromJsonAsync<ProfileScriptPreviewDto>($"/api/v1/downloads/{profile.Id}/preview"))!;

        preview.Script.Should().Be(downloadBody);
    }

    [Fact]
    public async Task GET_preview_unknown_id_returns_404()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{Guid.NewGuid()}/preview");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_preview_other_users_profile_returns_404()
    {
        using HttpClient owner = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(owner, "Work");

        using HttpClient other = CreateAuthed();
        HttpResponseMessage response = await other.GetAsync($"/api/v1/downloads/{profile.Id}/preview");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_preview_unauthenticated_returns_401()
    {
        using HttpClient anon = _factory.CreateClient();

        HttpResponseMessage response = await anon.GetAsync($"/api/v1/downloads/{Guid.NewGuid()}/preview");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
