using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Preferences;

[Collection("WebApi")]
public sealed class PreferencesEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task Get_WithoutBearer_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/preferences");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_WithoutScope_Returns403()
    {
        using HttpClient client = _factory.WithTestAuth(b =>
            b.WithOid(Guid.NewGuid()).WithoutScope()).CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/preferences");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Get_WithAuthAndNoPriorPut_Returns404()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/preferences");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_ThenGet_ReturnsCorrectValues()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        HttpResponseMessage put = await client.PutAsJsonAsync("/api/v1/preferences",
            new UpdateUserPreferenceDto(50, true));
        put.StatusCode.Should().Be(HttpStatusCode.OK);

        HttpResponseMessage get = await client.GetAsync("/api/v1/preferences");

        get.StatusCode.Should().Be(HttpStatusCode.OK);
        UserPreferenceDto? body = await get.Content.ReadFromJsonAsync<UserPreferenceDto>();
        body!.RowsPerPage.Should().Be(50);
        body.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task Put_WithInvalidRowsPerPage_Returns400WithProblemJson()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PutAsJsonAsync("/api/v1/preferences",
            new UpdateUserPreferenceDto(7, false));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("title").GetString().Should().Be("Validation failed");
        root.GetProperty("status").GetInt32().Should().Be(400);
        root.GetProperty("errors").TryGetProperty("Dto.RowsPerPage", out _).Should().BeTrue();
    }

    [Fact]
    public async Task Put_ThenPutAgain_Returns200WithUpdatedValues()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        HttpResponseMessage first = await client.PutAsJsonAsync("/api/v1/preferences",
            new UpdateUserPreferenceDto(10, false));
        first.StatusCode.Should().Be(HttpStatusCode.OK);

        HttpResponseMessage second = await client.PutAsJsonAsync("/api/v1/preferences",
            new UpdateUserPreferenceDto(100, true));

        second.StatusCode.Should().Be(HttpStatusCode.OK);
        UserPreferenceDto? body = await second.Content.ReadFromJsonAsync<UserPreferenceDto>();
        body!.RowsPerPage.Should().Be(100);
        body.DarkMode.Should().BeTrue();
    }

    public void Dispose() => _factory.Dispose();
}
