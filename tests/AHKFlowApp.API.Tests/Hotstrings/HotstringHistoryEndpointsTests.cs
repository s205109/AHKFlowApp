using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringHistoryEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    private static async Task<HotstringDto> CreateAsync(HttpClient client, string trigger)
    {
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/hotstrings", new CreateHotstringDto(trigger, "original"));
        created.EnsureSuccessStatusCode();

        return (await created.Content.ReadFromJsonAsync<HotstringDto>())!;
    }

    [Fact]
    public async Task History_AfterEdit_ListsVersionAndVersionDetailReturnsSnapshot()
    {
        using HttpClient client = CreateAuthed();
        HotstringDto dto = await CreateAsync(client, "he1");
        HttpResponseMessage put = await client.PutAsJsonAsync($"/api/v1/hotstrings/{dto.Id}",
            new UpdateHotstringDto("he1", "changed", null, true, true, true, null));
        put.EnsureSuccessStatusCode();

        HistoryEntryDto[]? entries = await client.GetFromJsonAsync<HistoryEntryDto[]>(
            $"/api/v1/hotstrings/{dto.Id}/history");
        entries.Should().ContainSingle();
        entries![0].Version.Should().Be(1);

        HotstringHistoryVersionDto? version = await client.GetFromJsonAsync<HotstringHistoryVersionDto>(
            $"/api/v1/hotstrings/{dto.Id}/history/1");
        version!.Snapshot.Replacement.Should().Be("original");
    }

    [Fact]
    public async Task History_OtherUsersItem_Returns404()
    {
        using HttpClient a = CreateAuthed();
        HotstringDto dto = await CreateAsync(a, "he2");

        using HttpClient b = CreateAuthed();
        HttpResponseMessage response = await b.GetAsync($"/api/v1/hotstrings/{dto.Id}/history");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Revert_RestoresPreviousStateAndReturnsUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HotstringDto dto = await CreateAsync(client, "he3");
        HttpResponseMessage put = await client.PutAsJsonAsync($"/api/v1/hotstrings/{dto.Id}",
            new UpdateHotstringDto("he3", "changed", null, true, true, true, null));
        put.EnsureSuccessStatusCode();

        HttpResponseMessage revert = await client.PostAsync(
            $"/api/v1/hotstrings/{dto.Id}/history/1/revert", content: null);

        revert.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? reverted = await revert.Content.ReadFromJsonAsync<HotstringDto>();
        reverted!.Replacement.Should().Be("original");
    }

    [Fact]
    public async Task DeleteRestorePurge_RoundTripsThroughRecycleBin()
    {
        using HttpClient client = CreateAuthed();
        HotstringDto dto = await CreateAsync(client, "he4");

        (await client.DeleteAsync($"/api/v1/hotstrings/{dto.Id}")).EnsureSuccessStatusCode();

        DeletedHotstringDto[]? deleted = await client.GetFromJsonAsync<DeletedHotstringDto[]>(
            "/api/v1/hotstrings/deleted");
        deleted.Should().Contain(d => d.Id == dto.Id);

        HttpResponseMessage restore = await client.PostAsync($"/api/v1/hotstrings/{dto.Id}/restore", content: null);
        restore.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? restored = await restore.Content.ReadFromJsonAsync<HotstringDto>();
        restored!.Id.Should().Be(dto.Id);
        restored.Trigger.Should().Be("he4");

        (await client.DeleteAsync($"/api/v1/hotstrings/{dto.Id}")).EnsureSuccessStatusCode();
        HttpResponseMessage purge = await client.DeleteAsync($"/api/v1/hotstrings/deleted/{dto.Id}");
        purge.StatusCode.Should().Be(HttpStatusCode.NoContent);

        DeletedHotstringDto[]? after = await client.GetFromJsonAsync<DeletedHotstringDto[]>(
            "/api/v1/hotstrings/deleted");
        after.Should().NotContain(d => d.Id == dto.Id);
        HttpResponseMessage history = await client.GetAsync($"/api/v1/hotstrings/{dto.Id}/history");
        history.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Endpoints_WithoutAuth_Return401()
    {
        using HttpClient anon = _factory.CreateClient();

        (await anon.GetAsync($"/api/v1/hotstrings/{Guid.NewGuid()}/history"))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await anon.GetAsync("/api/v1/hotstrings/deleted"))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
