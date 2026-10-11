using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace AHKFlowApp.API.Tests.Hotkeys;

[Collection("WebApi")]
public sealed class HotkeyHistoryEndpointsTests(ApiTestFixture fixture)
{
    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    private static async Task<HotkeyDto> CreateAsync(HttpClient client, string description, string key)
    {
        HttpResponseMessage created = await client.PostAsJsonAsync(
            "/api/v1/hotkeys",
            new CreateHotkeyDto(description, key, HotkeyActionKind.Disable, AppliesToAllProfiles: true));
        created.EnsureSuccessStatusCode();

        return (await created.Content.ReadFromJsonAsync<HotkeyDto>())!;
    }

    private static UpdateHotkeyDto EditHotkey(string description, string key) =>
        new(description, key, HotkeyActionKind.Disable,
            Ctrl: false, Alt: false, Shift: false, Win: false,
            Text: null, SendKeysContent: null, RunTarget: null, RunTargetKind: null,
            WindowOp: null, RemapDest: null, Body: null,
            ProfileIds: null, AppliesToAllProfiles: true);

    [Fact]
    public async Task History_AfterEdit_ListsVersionAndVersionDetailReturnsSnapshot()
    {
        using HttpClient client = CreateAuthed();
        HotkeyDto dto = await CreateAsync(client, "he1 original", "f16");
        HttpResponseMessage put = await client.PutAsJsonAsync($"/api/v1/hotkeys/{dto.Id}",
            EditHotkey("he1 changed", "f16"));
        put.EnsureSuccessStatusCode();

        HistoryEntryDto[]? entries = await client.GetFromJsonAsync<HistoryEntryDto[]>(
            $"/api/v1/hotkeys/{dto.Id}/history");
        entries.Should().ContainSingle();
        entries![0].Version.Should().Be(1);

        HotkeyHistoryVersionDto? version = await client.GetFromJsonAsync<HotkeyHistoryVersionDto>(
            $"/api/v1/hotkeys/{dto.Id}/history/1");
        version!.Snapshot.Description.Should().Be("he1 original");
    }

    [Fact]
    public async Task History_OtherUsersItem_Returns404()
    {
        using HttpClient a = CreateAuthed();
        HotkeyDto dto = await CreateAsync(a, "he2", "f17");

        using HttpClient b = CreateAuthed();
        HttpResponseMessage response = await b.GetAsync($"/api/v1/hotkeys/{dto.Id}/history");

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Revert_RestoresPreviousStateAndReturnsUpdatedDto()
    {
        using HttpClient client = CreateAuthed();
        HotkeyDto dto = await CreateAsync(client, "he3 original", "f18");
        HttpResponseMessage put = await client.PutAsJsonAsync($"/api/v1/hotkeys/{dto.Id}",
            EditHotkey("he3 changed", "f18"));
        put.EnsureSuccessStatusCode();

        HttpResponseMessage revert = await client.PostAsync(
            $"/api/v1/hotkeys/{dto.Id}/history/1/revert", content: null);

        revert.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyDto? reverted = await revert.Content.ReadFromJsonAsync<HotkeyDto>();
        reverted!.Description.Should().Be("he3 original");
    }

    [Fact]
    public async Task DeleteRestorePurge_RoundTripsThroughRecycleBin()
    {
        using HttpClient client = CreateAuthed();
        HotkeyDto dto = await CreateAsync(client, "he4", "f19");

        (await client.DeleteAsync($"/api/v1/hotkeys/{dto.Id}")).EnsureSuccessStatusCode();

        DeletedHotkeyDto[]? deleted = await client.GetFromJsonAsync<DeletedHotkeyDto[]>(
            "/api/v1/hotkeys/deleted");
        deleted.Should().Contain(d => d.Id == dto.Id);

        HttpResponseMessage restore = await client.PostAsync($"/api/v1/hotkeys/{dto.Id}/restore", content: null);
        restore.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyDto? restored = await restore.Content.ReadFromJsonAsync<HotkeyDto>();
        restored!.Id.Should().Be(dto.Id);
        restored.Key.Should().Be("F19");

        (await client.DeleteAsync($"/api/v1/hotkeys/{dto.Id}")).EnsureSuccessStatusCode();
        HttpResponseMessage purge = await client.DeleteAsync($"/api/v1/hotkeys/deleted/{dto.Id}");
        purge.StatusCode.Should().Be(HttpStatusCode.NoContent);

        DeletedHotkeyDto[]? after = await client.GetFromJsonAsync<DeletedHotkeyDto[]>(
            "/api/v1/hotkeys/deleted");
        after.Should().NotContain(d => d.Id == dto.Id);
        HttpResponseMessage history = await client.GetAsync($"/api/v1/hotkeys/{dto.Id}/history");
        history.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Revert_SnapshotFailsCurrentRules_Returns400WithTheRuleMessage()
    {
        var oid = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);
        HotkeyDto dto = await CreateAsync(client, "he6 original", "f17");

        // Plant an Edit Snapshot whose Key the canonical registry refuses. That check landed
        // after Snapshots started being written, so a stored row can hold such a Key.
        await using (AsyncServiceScope scope = _factory.Services.CreateAsyncScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            HotkeySnapshot bad = new(
                Description: "he6 original", Key: "NotAKeyName",
                Ctrl: true, Alt: false, Shift: false, Win: false,
                AppliesToAllProfiles: true, ProfileIds: [], CategoryIds: [],
                CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
                ActionKind: HotkeyActionKind.Run, RunTarget: "notepad.exe",
                RunTargetKind: RunTargetKind.Application);

            db.EntityHistories.Add(EntityHistory.Create(
                oid, TrackedEntityType.Hotkey, dto.Id, version: 1, HistoryChangeType.Edit,
                schemaVersion: 1, JsonSerializer.Serialize(bad), TimeProvider.System));
            await db.SaveChangesAsync();
        }

        HttpResponseMessage revert = await client.PostAsync(
            $"/api/v1/hotkeys/{dto.Id}/history/1/revert", content: null);

        revert.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        string body = await revert.Content.ReadAsStringAsync();
        body.Should().Contain("Key must be a known key name");
    }

    [Fact]
    public async Task Restore_SnapshotFailsCurrentRules_Returns200AttachedToNoProfile()
    {
        var oid = Guid.NewGuid();
        var id = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);

        // A Delete tombstone, planted directly: the API would refuse to create this Key.
        await using (AsyncServiceScope scope = _factory.Services.CreateAsyncScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            HotkeySnapshot bad = new(
                Description: "he7 original", Key: "NotAKeyName",
                Ctrl: true, Alt: false, Shift: false, Win: false,
                AppliesToAllProfiles: true, ProfileIds: [], CategoryIds: [],
                CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
                ActionKind: HotkeyActionKind.Run, RunTarget: "notepad.exe",
                RunTargetKind: RunTargetKind.Application);

            db.EntityHistories.Add(EntityHistory.Create(
                oid, TrackedEntityType.Hotkey, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(bad), TimeProvider.System));
            await db.SaveChangesAsync();
        }

        HttpResponseMessage restore = await client.PostAsync(
            $"/api/v1/hotkeys/{id}/restore", content: null);

        restore.StatusCode.Should().Be(HttpStatusCode.OK);
        HotkeyDto? restored = await restore.Content.ReadFromJsonAsync<HotkeyDto>();

        restored!.Id.Should().Be(id);
        restored.AppliesToAllProfiles.Should().BeFalse();
        restored.ProfileIds.Should().BeEmpty();
        restored.RestoreWarnings.Should().NotBeNullOrEmpty();
    }

    [Fact]
    public async Task Endpoints_WithoutAuth_Return401()
    {
        using HttpClient anon = _factory.CreateClient();

        (await anon.GetAsync($"/api/v1/hotkeys/{Guid.NewGuid()}/history"))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        (await anon.GetAsync("/api/v1/hotkeys/deleted"))
            .StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
