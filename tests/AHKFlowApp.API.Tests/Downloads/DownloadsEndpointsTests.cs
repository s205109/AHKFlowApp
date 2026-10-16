using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Downloads;

[Collection("WebApi")]
public sealed class DownloadsEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    private static async Task<ProfileDto> CreateProfileAsync(HttpClient client, string name,
        string? headerTemplate = null, string? footerTemplate = null)
    {
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto(name, headerTemplate, footerTemplate));
        created.EnsureSuccessStatusCode();
        return (await created.Content.ReadFromJsonAsync<ProfileDto>())!;
    }

    [Fact]
    public async Task GET_per_profile_returns_text_plain_with_attachment_disposition()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Work");

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{profile.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("text/plain");
        response.Content.Headers.ContentType.CharSet.Should().Be("utf-8");
        response.Content.Headers.ContentDisposition!.DispositionType.Should().Be("attachment");
        response.Content.Headers.ContentDisposition.FileName.Should().Be("ahkflow_Work.ahk");
    }

    [Fact]
    public async Task GET_per_profile_body_starts_with_header_template()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Work");

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{profile.Id}");

        string body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("#Requires AutoHotkey v2.0");
        body.Should().Contain("; --- Hotstrings ---");
        body.Should().Contain("; --- Hotkeys ---");
    }

    [Fact]
    public async Task GET_per_profile_unknown_id_returns_404()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{Guid.NewGuid()}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_per_profile_other_users_id_returns_404()
    {
        using HttpClient theirClient = CreateAuthed(Guid.NewGuid());
        ProfileDto theirProfile = await CreateProfileAsync(theirClient, "Theirs");

        using HttpClient meClient = CreateAuthed();
        HttpResponseMessage response = await meClient.GetAsync($"/api/v1/downloads/{theirProfile.Id}");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task GET_per_profile_unauthenticated_returns_401()
    {
        using HttpClient anon = _factory.CreateClient();

        HttpResponseMessage response = await anon.GetAsync($"/api/v1/downloads/{Guid.NewGuid()}");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GET_zip_returns_application_zip_with_attachment_disposition()
    {
        using HttpClient client = CreateAuthed();
        await CreateProfileAsync(client, "Work");
        await CreateProfileAsync(client, "Personal");

        HttpResponseMessage response = await client.GetAsync("/api/v1/downloads/zip");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/zip");
        response.Content.Headers.ContentDisposition!.DispositionType.Should().Be("attachment");
        response.Content.Headers.ContentDisposition.FileName.Should().Be("ahkflow_scripts.zip");
    }

    [Fact]
    public async Task GET_zip_contains_one_entry_per_profile()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto _ = (await client.GetFromJsonAsync<List<ProfileDto>>("/api/v1/profiles"))!.Single();
        await CreateProfileAsync(client, "Work");
        await CreateProfileAsync(client, "Personal");

        HttpResponseMessage response = await client.GetAsync("/api/v1/downloads/zip");

        await using Stream stream = await response.Content.ReadAsStreamAsync();
        using ZipArchive zip = new(stream, ZipArchiveMode.Read);
        zip.Entries.Select(e => e.Name).Should().BeEquivalentTo(
            "ahkflow_Default.ahk", "ahkflow_Work.ahk", "ahkflow_Personal.ahk");
    }

    [Fact]
    public async Task GET_per_profile_and_zip_name_one_stem_when_the_cut_lands_on_an_underscore()
    {
        // Backlog 171. 63 letters, a space, then 'bbb': the stem's 64th character is the
        // underscore. Before the fix both names ended in '_.ahk'.
        string expected = "ahkflow_" + new string('a', 63) + ".ahk";
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, new string('a', 63) + " bbb");

        HttpResponseMessage single = await client.GetAsync($"/api/v1/downloads/{profile.Id}");
        HttpResponseMessage all = await client.GetAsync("/api/v1/downloads/zip");

        single.Content.Headers.ContentDisposition!.FileName.Should().Be(expected);
        await using Stream stream = await all.Content.ReadAsStreamAsync();
        using ZipArchive zip = new(stream, ZipArchiveMode.Read);
        zip.Entries.Select(e => e.Name).Should().Contain(expected);
    }

    [Fact]
    public async Task GET_zip_holds_the_default_profile_script_for_an_owner_who_never_listed_profiles()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/downloads/zip");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        await using Stream stream = await response.Content.ReadAsStreamAsync();
        using ZipArchive zip = new(stream, ZipArchiveMode.Read);
        zip.Entries.Select(e => e.Name).Should().Equal("ahkflow_Default.ahk");

        // The profiles page must then see the same single profile, not create a second one.
        List<ProfileDto>? profiles = await client.GetFromJsonAsync<List<ProfileDto>>("/api/v1/profiles");
        profiles.Should().ContainSingle().Which.Name.Should().Be("Default");
    }

    [Fact]
    public async Task GET_zip_unauthenticated_returns_401()
    {
        using HttpClient anon = _factory.CreateClient();

        HttpResponseMessage response = await anon.GetAsync("/api/v1/downloads/zip");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task GET_per_profile_renders_header_tokens_end_to_end()
    {
        using HttpClient client = CreateAuthed();
        ProfileDto profile = await CreateProfileAsync(client, "Renderer Test",
            headerTemplate: """
                ; {ProfileName} v{AppVersion} — {HotstringCount}h {HotkeyCount}k
                ; Generated {GeneratedAt:yyyy-MM-dd}

                """,
            footerTemplate: "");

        HttpResponseMessage response = await client.GetAsync($"/api/v1/downloads/{profile.Id}");
        response.EnsureSuccessStatusCode();
        string content = await response.Content.ReadAsStringAsync();

        content.Should().StartWith("; Renderer Test v");
        content.Should().Contain("0h 0k");
        content.Should().MatchRegex(@"Generated \d{4}-\d{2}-\d{2}");
    }
}
