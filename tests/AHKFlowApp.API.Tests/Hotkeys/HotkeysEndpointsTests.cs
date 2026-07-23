using System.Net;
using System.Net.Http.Json;
using System.Text;
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

    // W1 renamed the list filter from `action` to `actionKind`. Bind and filter behaviour is
    // pinned at the HTTP boundary because a rename that silently stopped binding would still
    // return 200 with a full list.
    [Fact]
    public async Task List_WithActionKind_FiltersToThatKindOnly()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Remap caps", "f9", HotkeyActionKind.Remap,
                Ctrl: true, RemapDest: "Ctrl", AppliesToAllProfiles: true));
        await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Launch editor", "f10", HotkeyActionKind.Run,
                Ctrl: true, RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application,
                AppliesToAllProfiles: true));

        HttpResponseMessage response = await client.GetAsync("/api/v1/hotkeys?actionKind=Remap&pageSize=200");

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? body = await response.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.Items.Should().NotBeEmpty();
        body.Items.Should().OnlyContain(h => h.ActionKind == HotkeyActionKind.Remap);
        body.Items.Should().Contain(h => h.Key == "F9");
        body.Items.Should().NotContain(h => h.Key == "F10");
    }

    // ASP.NET Core ignores query parameters it cannot bind, so a client still sending the
    // pre-W1 `action` / `parametersFilter` names gets the full unfiltered list rather than an
    // error. Documenting that here so the silent-wrong-answer is a known contract, not a surprise.
    [Fact]
    public async Task List_WithLegacyActionParameters_IgnoresThemAndReturnsUnfilteredList()
    {
        var owner = Guid.NewGuid();
        using HttpClient client = CreateAuthed(owner);

        await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Launch editor", "f11", HotkeyActionKind.Run,
                Ctrl: true, RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application,
                AppliesToAllProfiles: true));
        await client.PostAsJsonAsync("/api/v1/hotkeys",
            new CreateHotkeyDto("Say hi", "f12", HotkeyActionKind.SendText,
                Ctrl: true, Text: "hi", AppliesToAllProfiles: true));

        HttpResponseMessage unfiltered = await client.GetAsync("/api/v1/hotkeys?pageSize=200");
        HttpResponseMessage legacy = await client.GetAsync("/api/v1/hotkeys?action=Run&parametersFilter=notepad&pageSize=200");

        legacy.StatusCode.Should().Be(HttpStatusCode.OK);
        PagedList<HotkeyDto>? all = await unfiltered.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        PagedList<HotkeyDto>? body = await legacy.Content.ReadFromJsonAsync<PagedList<HotkeyDto>>();
        body!.TotalCount.Should().Be(all!.TotalCount);
        body.Items.Should().Contain(h => h.Key == "F12");
    }

    // Golden per action kind: POST persists the typed columns AND the preview endpoint
    // (fed the same draft fields) reproduces the exact .ahk line the create would emit.
    // Pinning the literal snippet — not just the 201 — is the point of a golden: it proves
    // the round trip through validation, persistence, and HotkeyEmitter produced exactly
    // the expected AHK v2 syntax for every one of the seven kinds, not merely that some
    // string came back.
    [Theory]
    [MemberData(nameof(KindPayloads))]
    public async Task Post_EachActionKind_Returns201AndPersistsTypedColumns(
        CreateHotkeyDto dto, HotkeyActionKind expectedKind, string expectedSnippet)
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage res = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        res.StatusCode.Should().Be(HttpStatusCode.Created);
        HotkeyDto? created = await res.Content.ReadFromJsonAsync<HotkeyDto>();
        created!.ActionKind.Should().Be(expectedKind);

        // Unconditional, for every kind: the persisted typed columns must echo exactly what was
        // submitted. Since the request DTO only ever populates the column(s) its own kind owns —
        // every other typed column defaults to null — this single unconditional block both (a)
        // proves the owning column(s) round-tripped through creation and (b) proves every
        // non-owned column came back null, catching a mapping bug that wrote into the wrong
        // column. Being unconditional (no per-kind branching) means a new kind added to
        // KindPayloads gets this coverage automatically — there is nothing to remember to add.
        created.Text.Should().Be(dto.Text);
        created.SendKeysContent.Should().Be(dto.SendKeysContent);
        created.RunTarget.Should().Be(dto.RunTarget);
        created.RunTargetKind.Should().Be(dto.RunTargetKind);
        created.WindowOp.Should().Be(dto.WindowOp);
        created.RemapDest.Should().Be(dto.RemapDest);
        created.Body.Should().Be(dto.Body);

        // Independent read-back through the query path — not the POST echo — so the columns are
        // proven to have actually persisted and re-mapped, catching a write/read-mapping bug the
        // returned entity would hide.
        HotkeyDto? reloaded = await (await client.GetAsync($"/api/v1/hotkeys/{created.Id}"))
            .Content.ReadFromJsonAsync<HotkeyDto>();
        reloaded!.ActionKind.Should().Be(expectedKind);
        reloaded.Text.Should().Be(dto.Text);
        reloaded.SendKeysContent.Should().Be(dto.SendKeysContent);
        reloaded.RunTarget.Should().Be(dto.RunTarget);
        reloaded.RunTargetKind.Should().Be(dto.RunTargetKind);
        reloaded.WindowOp.Should().Be(dto.WindowOp);
        reloaded.RemapDest.Should().Be(dto.RemapDest);
        reloaded.Body.Should().Be(dto.Body);

        // Same draft fields as the create, through the preview endpoint, over real HTTP —
        // asserts the exact emitted .ahk line, not just that creation succeeded.
        var previewDto = new HotkeyPreviewRequestDto(
            dto.Description, dto.Key, dto.ActionKind,
            dto.Ctrl, dto.Alt, dto.Shift, dto.Win,
            dto.Text, dto.SendKeysContent, dto.RunTarget, dto.RunTargetKind,
            dto.WindowOp, dto.RemapDest, dto.Body);
        HttpResponseMessage previewRes = await client.PostAsJsonAsync("/api/v1/hotkeys/preview", previewDto);
        previewRes.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyPreviewDto? preview = await previewRes.Content.ReadFromJsonAsync<HotkeyPreviewDto>();
        preview!.Snippet.Should().Be(expectedSnippet);
    }

    // Non-canonical but valid inputs must be folded onto the single stored spelling (spec §8):
    // Key alias/case, and the SendKeys / RemapDest tokens' alias, case and vk/sc digit width.
    // Asserted on an independent read-back (query path), not the POST echo.
    [Theory]
    [InlineData("esc", "{vk1}", "Escape", "{vk01}")]        // key alias + SendKeys vk width
    [InlineData("ESCAPE", "{del}", "Escape", "{Delete}")]  // key case + SendKeys alias
    [InlineData("f5", "^{volume_up}", "F5", "^{Volume_Up}")] // key case + modifier preserved, registry case folded
    public async Task Post_SendKeys_CanonicalizesKeyAndTokenBeforePersisting(
        string submittedKey, string submittedContent, string expectedKey, string expectedContent)
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("Fold me", submittedKey, HotkeyActionKind.SendKeys,
            Ctrl: true, SendKeysContent: submittedContent, AppliesToAllProfiles: true);

        HotkeyDto? created = await (await client.PostAsJsonAsync("/api/v1/hotkeys", dto))
            .Content.ReadFromJsonAsync<HotkeyDto>();

        HotkeyDto? reloaded = await (await client.GetAsync($"/api/v1/hotkeys/{created!.Id}"))
            .Content.ReadFromJsonAsync<HotkeyDto>();
        reloaded!.Key.Should().Be(expectedKey);
        reloaded.SendKeysContent.Should().Be(expectedContent);

        // Preview fed the same non-canonical draft must produce the canonical emission — otherwise
        // the picker's live preview and the saved row would disagree.
        var previewDto = new HotkeyPreviewRequestDto(
            dto.Description, submittedKey, HotkeyActionKind.SendKeys,
            true, false, false, false, null, submittedContent, null, null, null, null, null);
        HotkeyPreviewDto? preview = await (await client.PostAsJsonAsync("/api/v1/hotkeys/preview", previewDto))
            .Content.ReadFromJsonAsync<HotkeyPreviewDto>();
        preview!.Snippet.Should().Contain(expectedContent).And.NotContain(submittedContent);
    }

    [Theory]
    [InlineData("esc", "Escape")]   // alias
    [InlineData("vk1", "vk01")]     // vk width
    [InlineData("CTRL", "Ctrl")]    // case
    public async Task Post_Remap_CanonicalizesDestBeforePersisting(string submittedDest, string expectedDest)
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("Remap me", "a", HotkeyActionKind.Remap,
            RemapDest: submittedDest, AppliesToAllProfiles: true);

        HotkeyDto? created = await (await client.PostAsJsonAsync("/api/v1/hotkeys", dto))
            .Content.ReadFromJsonAsync<HotkeyDto>();

        HotkeyDto? reloaded = await (await client.GetAsync($"/api/v1/hotkeys/{created!.Id}"))
            .Content.ReadFromJsonAsync<HotkeyDto>();
        reloaded!.RemapDest.Should().Be(expectedDest);
    }

    // AppliesToAllProfiles: true on every case — the create validator requires it (or a
    // non-empty ProfileIds) regardless of action kind; without it every case 400s on
    // Input.ProfileIds before the kind-specific logic under test ever runs.
    public static TheoryData<CreateHotkeyDto, HotkeyActionKind, string> KindPayloads() => new()
    {
        {
            new("Type text", "a", HotkeyActionKind.SendText, Ctrl: true, Text: "hi", AppliesToAllProfiles: true),
            HotkeyActionKind.SendText,
            "; Type text\n^a::SendText(\"hi\")"
        },
        {
            new("Send keys", "b", HotkeyActionKind.SendKeys, Ctrl: true, SendKeysContent: "{Up}", AppliesToAllProfiles: true),
            HotkeyActionKind.SendKeys,
            "; Send keys\n$^b::Send(\"{Up}\")"
        },
        {
            new("Run app", "c", HotkeyActionKind.Run, Ctrl: true, RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application, AppliesToAllProfiles: true),
            HotkeyActionKind.Run,
            "; Run app\n^c::Run(\"notepad.exe\")"
        },
        {
            new("Minimize", "d", HotkeyActionKind.Window, Ctrl: true, WindowOp: WindowOp.Minimize, AppliesToAllProfiles: true),
            HotkeyActionKind.Window,
            "; Minimize\n^d::WinMinimize(\"A\")"
        },
        {
            new("Remap", "CapsLock", HotkeyActionKind.Remap, RemapDest: "Ctrl", AppliesToAllProfiles: true),
            HotkeyActionKind.Remap,
            "; Remap\nCapsLock::Ctrl"
        },
        {
            new("Disable", "F1", HotkeyActionKind.Disable, AppliesToAllProfiles: true),
            HotkeyActionKind.Disable,
            "; Disable\nF1::return"
        },
        {
            new("Raw", "e", HotkeyActionKind.Raw, Ctrl: true, Body: "MsgBox \"hi\"", AppliesToAllProfiles: true),
            HotkeyActionKind.Raw,
            "; Raw\n^e::MsgBox \"hi\""
        },
    };

    // KindPayloads exercises at most one modifier per case, so it can never pin the emitter's
    // fixed modifier order (^ ! + # — Ctrl, Alt, Shift, Win per HotkeyEmitter). This case sets
    // all four simultaneously; the expected snippet is derived from BuildModifiers' literal
    // append order in HotkeyEmitter, not from observed output.
    [Fact]
    public async Task Post_AllModifiersSet_EmitsInFixedOrder()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("All modifiers", "q", HotkeyActionKind.SendText,
            Ctrl: true, Alt: true, Shift: true, Win: true, Text: "hi", AppliesToAllProfiles: true);

        HttpResponseMessage res = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        res.StatusCode.Should().Be(HttpStatusCode.Created);
        HotkeyDto? created = await res.Content.ReadFromJsonAsync<HotkeyDto>();
        created!.Ctrl.Should().BeTrue();
        created.Alt.Should().BeTrue();
        created.Shift.Should().BeTrue();
        created.Win.Should().BeTrue();

        var previewDto = new HotkeyPreviewRequestDto(
            dto.Description, dto.Key, dto.ActionKind,
            dto.Ctrl, dto.Alt, dto.Shift, dto.Win,
            dto.Text, dto.SendKeysContent, dto.RunTarget, dto.RunTargetKind,
            dto.WindowOp, dto.RemapDest, dto.Body);
        HttpResponseMessage previewRes = await client.PostAsJsonAsync("/api/v1/hotkeys/preview", previewDto);
        previewRes.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyPreviewDto? preview = await previewRes.Content.ReadFromJsonAsync<HotkeyPreviewDto>();
        preview!.Snippet.Should().Be("; All modifiers\n^!+#q::SendText(\"hi\")");
    }

    // Raw JSON, not a typed DTO: an out-of-range int is exactly what a hand-rolled client sends,
    // and it is the only way to reach the undefined-enum path the validator now guards. Must be
    // 400 from validation, never 500 from the emitter — and the ProblemDetails must name the field
    // that is actually wrong, so a status-only assertion is not enough.
    [Theory]
    [InlineData("{\"description\":\"Bad\",\"key\":\"a\",\"ctrl\":true,\"actionKind\":99}", "ActionKind")]
    [InlineData("{\"description\":\"Bad\",\"key\":\"a\",\"ctrl\":true,\"actionKind\":3,\"windowOp\":99}", "WindowOp")]
    [InlineData("{\"description\":\"Bad\",\"key\":\"a\",\"ctrl\":true,\"actionKind\":2,\"runTarget\":\"notepad\",\"runTargetKind\":99}", "RunTargetKind")]
    public async Task Post_UndefinedEnumValue_Returns400NamingField(string json, string expectedField)
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage res = await client.PostAsync("/api/v1/hotkeys",
            new StringContent(json, Encoding.UTF8, "application/json"));

        res.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await res.Content.ReadAsStringAsync()).Should().Contain(expectedField);
    }

    [Fact]
    public async Task Post_MalformedSendKeys_Returns400NamingField()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("Bad", "a", HotkeyActionKind.SendKeys, Ctrl: true, SendKeysContent: "Volume_Up");

        HttpResponseMessage res = await client.PostAsJsonAsync("/api/v1/hotkeys", dto);

        res.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await res.Content.ReadAsStringAsync()).Should().Contain("SendKeysContent");
    }

    [Fact]
    public async Task Post_DuplicateKeyAndModifiers_Returns409()
    {
        using HttpClient client = CreateAuthed();
        var dto = new CreateHotkeyDto("First", "z", HotkeyActionKind.Disable, AppliesToAllProfiles: true);
        (await client.PostAsJsonAsync("/api/v1/hotkeys", dto)).StatusCode.Should().Be(HttpStatusCode.Created);

        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/hotkeys",
            dto with { Description = "Second" });

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }
}
