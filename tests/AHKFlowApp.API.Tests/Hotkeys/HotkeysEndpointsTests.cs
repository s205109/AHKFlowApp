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
public sealed class HotkeysEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    // A hotkey whose action carries no payload, for the many cases that only exercise CRUD,
    // ownership or paging and do not care which typed action the row holds.
    private static CreateHotkeyDto NewHotkey(
        string description,
        string key,
        bool ctrl = true,
        bool appliesToAllProfiles = true) =>
        new(description, key, HotkeyActionKind.Disable,
            Ctrl: ctrl, AppliesToAllProfiles: appliesToAllProfiles);

    private static UpdateHotkeyDto EditHotkey(string description, string key, bool ctrl = true) =>
        new(description, key, HotkeyActionKind.Disable,
            Ctrl: ctrl, Alt: false, Shift: false, Win: false,
            Text: null, SendKeysContent: null, RunTarget: null, RunTargetKind: null,
            WindowOp: null, RemapDest: null, Body: null,
            ProfileIds: null, AppliesToAllProfiles: true);

    [Fact]
    public async Task Post_CreatesAndReturns201WithLocation()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("Open Notepad", "n", HotkeyActionKind.Run,
            Ctrl: true, RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application,
            AppliesToAllProfiles: true);

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        response.Headers.Location.Should().NotBeNull();

        HotkeyDto? body = await response.Content.ReadFromJsonAsync<HotkeyDto>();
        body!.Key.Should().Be("n");
        body.Ctrl.Should().BeTrue();
        body.Description.Should().Be("Open Notepad");
        body.AppliesToAllProfiles.Should().BeTrue();
        body.ActionKind.Should().Be(HotkeyActionKind.Run);
        body.RunTarget.Should().Be("notepad.exe");
        body.RunTargetKind.Should().Be(RunTargetKind.Application);
        body.Text.Should().BeNull();
        body.SendKeysContent.Should().BeNull();
        body.Body.Should().BeNull();

        HttpResponseMessage get = await client.GetAsync(response.Headers.Location);
        get.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task Put_ChangingActionKind_ReplacesTypedFields()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Launch", "f8", HotkeyActionKind.Run,
                Ctrl: true, RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application,
                AppliesToAllProfiles: true));
        HotkeyDto? before = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        HttpResponseMessage put = await client.PutAsJsonAsync(
            $"/api/v1/hotkeys/{before!.Id}",
            new UpdateHotkeyDto("Now sends keys", "f8", HotkeyActionKind.SendKeys,
                Ctrl: true, Alt: false, Shift: false, Win: false,
                Text: null, SendKeysContent: "{Volume_Up}", RunTarget: null, RunTargetKind: null,
                WindowOp: null, RemapDest: null, Body: null,
                ProfileIds: null, AppliesToAllProfiles: true));

        put.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyDto? after = await put.Content.ReadFromJsonAsync<HotkeyDto>();
        after!.ActionKind.Should().Be(HotkeyActionKind.SendKeys);
        after.SendKeysContent.Should().Be("{Volume_Up}");
        after.RunTarget.Should().BeNull();
        after.RunTargetKind.Should().BeNull();
    }

    [Fact]
    public async Task Post_InvalidBody_Returns400()
    {
        using HttpClient client = CreateAuthed();
        // Empty description and key — both required
        CreateHotkeyDto dto = NewHotkey("", "");

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Post_DuplicateKeyModifiers_Returns409_WithProblemDetails()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);
        CreateHotkeyDto dto = NewHotkey("First", "f1");

        HttpResponseMessage first = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);
        first.StatusCode.Should().Be(HttpStatusCode.Created);

        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/hotkeys",
            NewHotkey("Duplicate", "f1"));

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
        UpdateHotkeyDto dto = EditHotkey("Updated", "n");

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
            NewHotkey("Owner A hotkey", "f1"));
        HotkeyDto? body = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        using HttpClient b = CreateAuthed(ownerB);
        HttpResponseMessage response = await b.PutAsJsonAsync(
            $"/api/v1/hotkeys/{body!.Id}",
            EditHotkey("Hijacked", "f1"));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Put_Success_Returns200WithUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/hotkeys",
            NewHotkey("Before", "f3"));
        HotkeyDto? before = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        await Task.Delay(10);

        HttpResponseMessage put = await client.PutAsJsonAsync(
            $"/api/v1/hotkeys/{before!.Id}",
            EditHotkey("After", "f3"));

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
            NewHotkey("To delete", "f4"));
        HotkeyDto? body = await created.Content.ReadFromJsonAsync<HotkeyDto>();

        HttpResponseMessage del = await client.DeleteAsync($"/api/v1/hotkeys/{body!.Id}");
        del.StatusCode.Should().Be(HttpStatusCode.NoContent);

        HttpResponseMessage get = await client.GetAsync($"/api/v1/hotkeys/{body.Id}");
        get.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task BulkDelete_MixedOwnedForeignAndUnknown_ReturnsDeletedCountAndMissingIds()
    {
        var ownerA = Guid.NewGuid();
        var ownerB = Guid.NewGuid();
        using HttpClient a = CreateAuthed(ownerA);
        using HttpClient b = CreateAuthed(ownerB);

        HotkeyDto owned1 = (await (await a.PostAsJsonAsync(
            "/api/v1/hotkeys", NewHotkey("Bulk A", "f5"))).Content
            .ReadFromJsonAsync<HotkeyDto>())!;
        HotkeyDto owned2 = (await (await a.PostAsJsonAsync(
            "/api/v1/hotkeys", NewHotkey("Bulk B", "f6"))).Content
            .ReadFromJsonAsync<HotkeyDto>())!;
        HotkeyDto foreign = (await (await b.PostAsJsonAsync(
            "/api/v1/hotkeys", NewHotkey("Bulk foreign", "f7"))).Content
            .ReadFromJsonAsync<HotkeyDto>())!;
        var unknown = Guid.NewGuid();

        HttpResponseMessage response = await a.PostAsJsonAsync(
            "/api/v1/hotkeys/bulk-delete",
            new BulkDeleteRequestDto([owned1.Id, foreign.Id, unknown, owned2.Id]));

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        BulkDeleteResultDto result = (await response.Content.ReadFromJsonAsync<BulkDeleteResultDto>())!;
        result.DeletedCount.Should().Be(2);
        result.MissingIds.Should().BeEquivalentTo([foreign.Id, unknown]);

        (await a.GetAsync($"/api/v1/hotkeys/{owned1.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await a.GetAsync($"/api/v1/hotkeys/{owned2.Id}")).StatusCode.Should().Be(HttpStatusCode.NotFound);
        (await b.GetAsync($"/api/v1/hotkeys/{foreign.Id}")).StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task BulkDelete_OverCap_Returns400()
    {
        using HttpClient client = CreateAuthed();
        Guid[] ids = [.. Enumerable.Range(0, 501).Select(_ => Guid.NewGuid())];

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotkeys/bulk-delete",
            new BulkDeleteRequestDto(ids));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task BulkDelete_Unauthenticated_Returns401()
    {
        using HttpClient anon = _factory.CreateClient();

        HttpResponseMessage response = await anon.PostAsJsonAsync(
            "/api/v1/hotkeys/bulk-delete",
            new BulkDeleteRequestDto([Guid.NewGuid()]));

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task BulkDelete_EmptyIds_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/hotkeys/bulk-delete",
            new BulkDeleteRequestDto([]));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task List_WithPagination_ReturnsSlice()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        for (int i = 0; i < 5; i++)
            await client.PostAsJsonAsync("/api/v1/hotkeys",
                NewHotkey($"Hotkey {i}", $"f{i + 1}"));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?page=2&pageSize=2");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.TotalCount.Should().Be(17);  // 5 created + 12 lazy-seeded in dev
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
            NewHotkey("Help", "F1"));
        await client.PostAsJsonAsync("/api/v1/hotkeys",
            NewHotkey("Rename", "F2"));

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
        using HttpClient client = _factory.CreateAuthenticatedClient(b => b.WithOid(Guid.NewGuid()).WithoutScope());

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys");

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Post_InvalidBody_ReturnsProblemDetailsWithErrors()
    {
        using HttpClient client = CreateAuthed();
        CreateHotkeyDto dto = NewHotkey("", "");

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

    [Fact]
    public async Task List_WithSortAndColumnFilter_ReturnsFilteredSortedRows()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotkeys",
            NewHotkey("MyCustom browser", "f3"));
        await client.PostAsJsonAsync("/api/v1/hotkeys",
            NewHotkey("MyCustom notepad", "f1"));
        await client.PostAsJsonAsync("/api/v1/hotkeys",
            NewHotkey("Lock workstation", "f2"));

        HttpResponseMessage response = await client.GetAsync(
            "/api/v1/hotkeys?descriptionFilter=MyCustom&sortField=key&sortDescending=false");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.Items.Select(h => h.Key).Should().Equal("F1", "F3");
    }

    [Fact]
    public async Task List_WithUnknownSortField_Returns400()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?sortField=ownerOid");

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }
}
