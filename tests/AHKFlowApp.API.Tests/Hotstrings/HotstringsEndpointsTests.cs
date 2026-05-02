using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotstrings;

[Collection("WebApi")]
public sealed class HotstringsEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task Post_CreatesAndReturns201WithLocation()
    {
        using HttpClient client = CreateAuthed();
        CreateHotstringDto dto = new("btw", "by the way");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        HotstringDto? body = await response.Content.ReadFromJsonAsync<HotstringDto>();
        body!.Trigger.Should().Be("btw");
        body.AppliesToAllProfiles.Should().BeTrue();
        body.ProfileIds.Should().BeEmpty();

        HttpResponseMessage get = await client.GetAsync(response.Headers.Location);
        get.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Post_InvalidBody_Returns400()
    {
        using HttpClient client = CreateAuthed();
        CreateHotstringDto dto = new("", "");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Post_DuplicateTrigger_Returns409_WithProblemDetails()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);
        CreateHotstringDto dto = new("dup", "x");

        HttpResponseMessage first = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
        second.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await second.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("type").GetString().Should().Be("https://tools.ietf.org/html/rfc9110#section-15.5.10");
        root.GetProperty("status").GetInt32().Should().Be(409);
        root.GetProperty("detail").GetString().Should().Contain("already exists");
    }

    [Fact]
    public async Task Put_UnknownId_Returns404_WithProblemDetails()
    {
        using HttpClient client = CreateAuthed();
        UpdateHotstringDto dto = new("x", "y", null, true, true, true);

        var unknownId = Guid.NewGuid();
        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/hotstrings/{unknownId}", dto);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_OtherUsersRow_Returns404()
    {
        var ownerA = Guid.NewGuid();
        var ownerB = Guid.NewGuid();

        using HttpClient a = CreateAuthed(ownerA);
        HttpResponseMessage created = await a.PostAsJsonAsync("/api/v1/hotstrings",
            new CreateHotstringDto("tenant-a", "x"));
        HotstringDto? body = await created.Content.ReadFromJsonAsync<HotstringDto>();

        using HttpClient b = CreateAuthed(ownerB);
        HttpResponseMessage response = await b.PutAsJsonAsync(
            $"/api/v1/hotstrings/{body!.Id}",
            new UpdateHotstringDto("tenant-a", "hijack", null, true, true, true));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_Success_Returns200WithUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotstrings",
            new CreateHotstringDto("upd", "before"));
        HotstringDto? before = await created.Content.ReadFromJsonAsync<HotstringDto>();

        await Task.Delay(10);

        HttpResponseMessage put = await client.PutAsJsonAsync(
            $"/api/v1/hotstrings/{before!.Id}",
            new UpdateHotstringDto("upd", "after", null, true, false, false));

        put.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? after = await put.Content.ReadFromJsonAsync<HotstringDto>();
        after!.Replacement.Should().Be("after");
        after.IsEndingCharacterRequired.Should().BeFalse();
        after.UpdatedAt.Should().BeOnOrAfter(before.CreatedAt);
    }

    [Fact]
    public async Task Delete_ThenGet_Returns404()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotstrings",
            new CreateHotstringDto("del", "x"));
        HotstringDto? body = await created.Content.ReadFromJsonAsync<HotstringDto>();

        HttpResponseMessage del = await client.DeleteAsync($"/api/v1/hotstrings/{body!.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        HttpResponseMessage get = await client.GetAsync($"/api/v1/hotstrings/{body.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task List_FiltersByProfileId_IncludesGlobalAndScoped()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("global", "x"));
        var anyProfileId = Guid.NewGuid();

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotstrings?profileId={anyProfileId}");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? pagedBody = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        pagedBody!.Items.Should().Contain(h => h.Trigger == "global" && h.AppliesToAllProfiles);
    }

    [Fact]
    public async Task List_WithPagination_ReturnsSlice()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        for (int i = 0; i < 5; i++)
            await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto($"p{i}", "x"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?page=2&pageSize=2");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? pagedBody = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        pagedBody!.TotalCount.Should().Be(5);
        pagedBody.Items.Should().HaveCount(2);
        pagedBody.Page.Should().Be(2);
    }

    [Fact]
    public async Task List_PageSizeTooLarge_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?pageSize=500");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task List_SearchByTrigger_FiltersResults()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("btw", "by the way"));
        await client.PostAsJsonAsync("/api/v1/hotstrings", new CreateHotstringDto("fyi", "for your info"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings?search=btw");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotstringDto>? pagedBody = await response.Content.ReadFromJsonAsync<PagedList<HotstringDto>>();
        pagedBody!.Items.Should().ContainSingle().Which.Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task List_SearchTooLong_Returns400()
    {
        using HttpClient client = CreateAuthed();
        string longSearch = new('x', 201);

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotstrings?search={longSearch}");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Get_WithoutBearer_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_WithoutScope_Returns403()
    {
        using HttpClient client = _factory.WithTestAuth(b =>
            b.WithOid(Guid.NewGuid()).WithoutScope()).CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotstrings");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Post_InvalidBody_ReturnsProblemDetailsWithErrors()
    {
        using HttpClient client = CreateAuthed();
        CreateHotstringDto dto = new("", "");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotstrings", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;

        root.GetProperty("title").GetString().Should().Be("Validation failed");
        root.GetProperty("status").GetInt32().Should().Be(400);

        JsonElement errors = root.GetProperty("errors");
        errors.TryGetProperty("Input.Trigger", out _).Should().BeTrue();
        errors.TryGetProperty("Input.Replacement", out _).Should().BeTrue();
    }

    public void Dispose() => _factory.Dispose();
}
