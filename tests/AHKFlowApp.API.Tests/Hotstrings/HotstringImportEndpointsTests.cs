using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringImportEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    [Fact]
    public async Task PostPreview_ReturnsRowsAndCounts()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import/preview", new PreviewHotstringImportRequestDto("::btw::by the way"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringImportPreviewDto? body = await response.Content.ReadFromJsonAsync<HotstringImportPreviewDto>();
        body!.ReadyCount.Should().Be(1);
        body.Rows.Should().ContainSingle();
    }

    [Fact]
    public async Task PostImport_CreatesHotstrings()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import", new ImportHotstringsRequestDto("::btw::by the way\n::omw::on my way"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringImportResultDto? body = await response.Content.ReadFromJsonAsync<HotstringImportResultDto>();
        body!.ImportedCount.Should().Be(2);

        HttpResponseMessage list = await client.GetAsync("/api/v1/hotstrings?pageSize=50");
        (await list.Content.ReadFromJsonAsync<PagedList<HotstringDto>>())!.TotalCount.Should().Be(2);
    }

    [Fact]
    public async Task PostImport_FullyDuplicate_Returns200WithZeroImported()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);
        await client.PostAsJsonAsync("/api/v1/hotstrings/import", new ImportHotstringsRequestDto("::btw::x"));

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import", new ImportHotstringsRequestDto("::btw::again"));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        (await response.Content.ReadFromJsonAsync<HotstringImportResultDto>())!.ImportedCount.Should().Be(0);
    }

    [Fact]
    public async Task PostImport_EmptyScript_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import", new ImportHotstringsRequestDto(""));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task PostPreview_Unauthenticated_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotstrings/import/preview", new PreviewHotstringImportRequestDto("::btw::x"));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
