using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotkeys;

[Collection("WebApi")]
public sealed class HotkeysEndpointsTests(SqlContainerFixture sqlFixture) : IDisposable
{
    private readonly CustomWebApplicationFactory _factory = new(sqlFixture);

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.WithTestAuth(b => b.WithOid(oid ?? Guid.NewGuid())).CreateClient();

    [Fact]
    public async Task Post_CreatesAndReturns201WithLocation()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("Open Notepad", "n", Ctrl: true, AppliesToAllProfiles: true);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        HotkeyDto? body = await response.Content.ReadFromJsonAsync<HotkeyDto>();
        body!.Key.Should().Be("n");
        body.Ctrl.Should().BeTrue();
        body.Description.Should().Be("Open Notepad");
        body.AppliesToAllProfiles.Should().BeTrue();

        HttpResponseMessage get = await client.GetAsync(response.Headers.Location);
        get.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Post_InvalidBody_Returns400()
    {
        using HttpClient client = CreateAuthed();
        // Empty description and key — both required
        var dto = new CreateHotkeyDto("", "", AppliesToAllProfiles: true);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Post_DuplicateKeyModifiers_Returns409_WithProblemDetails()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);
        var dto = new CreateHotkeyDto("First", "f1", Ctrl: true, AppliesToAllProfiles: true);

        HttpResponseMessage first = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Duplicate", "f1", Ctrl: true, AppliesToAllProfiles: true));

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
        second.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await second.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("type").GetString().Should().Be("https://tools.ietf.org/html/rfc9110#section-15.5.10");
        root.GetProperty("title").GetString().Should().Be("Conflict");
        root.GetProperty("status").GetInt32().Should().Be(409);
        root.GetProperty("detail").GetString().Should().Contain("already exists");
        root.GetProperty("instance").GetString().Should().Be("/api/v1/hotkeys");
        root.GetProperty("traceId").GetString().Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task Put_UnknownId_Returns404_WithProblemDetails()
    {
        using HttpClient client = CreateAuthed();
        var dto = new UpdateHotkeyDto("Updated", "n", true, false, false, false, HotkeyAction.Run, "", null, true);

        var unknownId = Guid.NewGuid();
        HttpResponseMessage response = await client.PutAsJsonAsync(
            $"/api/v1/hotkeys/{unknownId}", dto);

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;
        root.GetProperty("type").GetString().Should().Be("https://tools.ietf.org/html/rfc9110#section-15.5.5");
        root.GetProperty("title").GetString().Should().Be("Resource not found");
        root.GetProperty("status").GetInt32().Should().Be(404);
        root.GetProperty("instance").GetString().Should().Be($"/api/v1/hotkeys/{unknownId}");
        root.GetProperty("traceId").GetString().Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task Put_OtherUsersRow_Returns404()
    {
        var ownerA = Guid.NewGuid();
        var ownerB = Guid.NewGuid();

        using HttpClient a = CreateAuthed(ownerA);
        HttpResponseMessage created = await a.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Owner A hotkey", "f1", Ctrl: true, AppliesToAllProfiles: true));
        HotkeyDto? body = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        using HttpClient b = CreateAuthed(ownerB);
        HttpResponseMessage response = await b.PutAsJsonAsync(
            $"/api/v1/hotkeys/{body!.Id}",
            new UpdateHotkeyDto("Hijacked", "f1", true, false, false, false, HotkeyAction.Run, "", null, true));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_Success_Returns200WithUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Before", "f3", Ctrl: true, AppliesToAllProfiles: true));
        HotkeyDto? before = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        await Task.Delay(10);

        HttpResponseMessage put = await client.PutAsJsonAsync(
            $"/api/v1/hotkeys/{before!.Id}",
            new UpdateHotkeyDto("After", "f3", true, false, false, false, HotkeyAction.Run, "", null, true));

        put.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyDto? after = await put.Content.ReadFromJsonAsync<HotkeyDto>();
        after!.Description.Should().Be("After");
        after.UpdatedAt.Should().BeOnOrAfter(before.CreatedAt);
    }

    [Fact]
    public async Task Delete_ThenGet_Returns404()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("To delete", "f4", Ctrl: true, AppliesToAllProfiles: true));
        HotkeyDto? body = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        HttpResponseMessage del = await client.DeleteAsync($"/api/v1/hotkeys/{body!.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        HttpResponseMessage get = await client.GetAsync($"/api/v1/hotkeys/{body.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task List_WithPagination_ReturnsSlice()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        for (int i = 0; i < 5; i++)
            await client.PostAsJsonAsync("/api/v1/hotkeys",
                new CreateHotkeyDto($"Hotkey {i}", $"f{i + 1}", Ctrl: true, AppliesToAllProfiles: true));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?page=2&pageSize=2");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.TotalCount.Should().Be(5);
        body.Items.Should().HaveCount(2);
        body.Page.Should().Be(2);
    }

    [Fact]
    public async Task List_PageSizeTooLarge_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?pageSize=500");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task List_SearchByKey_FiltersResults()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Help", "F1", Ctrl: true, AppliesToAllProfiles: true));
        await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Rename", "F2", Ctrl: true, AppliesToAllProfiles: true));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?search=F1");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.Items.Should().ContainSingle().Which.Key.Should().Be("F1");
    }

    [Fact]
    public async Task List_SearchTooLong_Returns400()
    {
        using HttpClient client = CreateAuthed();
        string longSearch = new('x', 201);

        HttpResponseMessage response = await client.GetAsync($"/api/v1/hotkeys?search={longSearch}");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Get_WithoutBearer_Returns401()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Get_WithoutScope_Returns403()
    {
        using HttpClient client = _factory.WithTestAuth(b =>
            b.WithOid(Guid.NewGuid()).WithoutScope()).CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Post_InvalidBody_ReturnsProblemDetailsWithErrors()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("", "", AppliesToAllProfiles: true);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        response.Content.Headers.ContentType!.MediaType.Should().Be("application/problem+json");

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        JsonElement root = doc.RootElement;

        root.GetProperty("title").GetString().Should().Be("Validation failed");
        root.GetProperty("status").GetInt32().Should().Be(400);
        root.GetProperty("detail").GetString().Should().NotBeNullOrWhiteSpace();

        JsonElement errors = root.GetProperty("errors");
        errors.TryGetProperty("Input.Description", out _).Should().BeTrue("validation errors should be keyed by DTO property path");
        errors.TryGetProperty("Input.Key", out _).Should().BeTrue();
    }

    public void Dispose() => _factory.Dispose();
}
