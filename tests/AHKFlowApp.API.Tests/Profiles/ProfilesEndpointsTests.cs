using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Profiles;

[Collection("WebApi")]
public sealed class ProfilesEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task GET_list_seeds_default_on_first_call()
    {
        using HttpClient client = CreateAuthed(Guid.NewGuid());

        HttpResponseMessage response = await client.GetAsync("/api/v1/profiles");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        IReadOnlyList<ProfileDto>? items = await response.Content.ReadFromJsonAsync<IReadOnlyList<ProfileDto>>();
        items.Should().ContainSingle().Which.IsDefault.Should().BeTrue();
    }

    [Fact]
    public async Task POST_creates_profile_returns_201_with_location()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Work"));

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();
    }

    [Fact]
    public async Task POST_returns_409_on_duplicate_name()
    {
        using HttpClient client = CreateAuthed();
        await client.PostAsJsonAsync("/api/v1/profiles", new CreateProfileDto("Work"));

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Work"));
        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task POST_returns_400_when_name_blank()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto(""));
        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task GET_id_returns_404_for_other_user_profile()
    {
        var otherOid = Guid.NewGuid();
        using HttpClient otherClient = CreateAuthed(otherOid);
        HttpResponseMessage created = await otherClient.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Theirs"));
        ProfileDto theirProfile = (await created.Content.ReadFromJsonAsync<ProfileDto>())!;

        using HttpClient meClient = CreateAuthed();
        HttpResponseMessage response = await meClient.GetAsync($"/api/v1/profiles/{theirProfile.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task PUT_updates_returns_200()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("Work"));
        ProfileDto p = (await created.Content.ReadFromJsonAsync<ProfileDto>())!;

        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/profiles/{p.Id}",
            new UpdateProfileDto("Work2", "h", "f", true));
        response.StatusCode.Should().Be(HttpStatusCode.OK);
        ProfileDto updated = (await response.Content.ReadFromJsonAsync<ProfileDto>())!;
        updated.Name.Should().Be("Work2");
    }

    [Fact]
    public async Task DELETE_returns_204()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/profiles", new CreateProfileDto("ToDelete"));
        ProfileDto p = (await created.Content.ReadFromJsonAsync<ProfileDto>())!;

        HttpResponseMessage response = await client.DeleteAsync($"/api/v1/profiles/{p.Id}");
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task GET_list_unauthenticated_returns_401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/profiles");
        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    public void Dispose() => _factory.Dispose();
}
