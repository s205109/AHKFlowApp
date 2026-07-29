using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.KnownShortcuts;

[Collection("WebApi")]
public sealed class KnownShortcutsControllerTests(ApiTestFixture fixture)
{
    private const string ExplorerId = "windows.file-explorer";

    private readonly CustomWebApplicationFactory _factory = fixture.Factory;

    private HttpClient CreateAuthed(Guid? oid = null) =>
        _factory.CreateAuthenticatedClient(b => b.WithOid(oid ?? Guid.NewGuid()));

    private static CreateCustomKnownShortcutDto NewRecord(
        string key = "F7",
        bool ctrl = true,
        string usedBy = "My notes tool",
        string does = "open my notes",
        ShortcutProtection protection = ShortcutProtection.Unknown) =>
        new(key, ctrl, Alt: false, Shift: false, Win: false,
            usedBy, ShortcutScope.Foreground, does, protection);

    [Fact]
    public async Task List_WithoutAuth_IsRefused()
    {
        using HttpClient client = _factory.CreateClient();

        HttpResponseMessage response = await client.GetAsync("/api/v1/knownshortcuts");

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task List_WithAuth_ReturnsTheManifestPlusOwnerRows()
    {
        using HttpClient client = CreateAuthed();

        ManagedKnownShortcutCatalogDto? before =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");

        await client.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord());

        ManagedKnownShortcutCatalogDto? after =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");

        before!.Shortcuts.Should().NotBeEmpty();
        after!.Shortcuts.Should().HaveCount(before.Shortcuts.Count + 1);
    }

    [Fact]
    public async Task Create_ValidRecord_ReturnsTheMergedListContainingTheNewUse()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord());

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        ManagedKnownShortcutCatalogDto? catalog =
            await response.Content.ReadFromJsonAsync<ManagedKnownShortcutCatalogDto>();

        ManagedShortcutUseDto use = catalog!.Shortcuts
            .SelectMany(s => s.Uses)
            .Single(u => u.UsedBy == "My notes tool");

        use.Origin.Should().Be(ShortcutRecordOrigin.Owner);
        use.OwnerRecordId.Should().NotBeNull();
        use.Does.Should().Be("open my notes");
    }

    [Fact]
    public async Task Create_SameCombinationAndUsedByTwice_IsAConflict()
    {
        using HttpClient client = CreateAuthed();

        await client.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord());
        HttpResponseMessage second = await client.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord());

        second.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Create_ClaimingProtected_IsRejected()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts", NewRecord(protection: ShortcutProtection.Protected));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        (await response.Content.ReadAsStringAsync()).Should()
            .Contain("Only built-in records can say Windows handles the keys itself.");
    }

    [Fact]
    public async Task Create_UnknownKey_IsRejected()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts", NewRecord(key: "NotAKey"));

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_SentConcurrently_YieldsOneCreatedAndTheRestConflict()
    {
        // A sequential duplicate never reaches the handler's catch: the AnyAsync check returns
        // first. Only overlapping requests can, and the invariant asserted here — never a 500,
        // never a second row — is what the race guard exists for.
        using HttpClient client = CreateAuthed();

        HttpResponseMessage[] responses = await Task.WhenAll(
            Enumerable.Range(0, 4).Select(_ =>
                client.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord())));

        responses.Count(r => r.StatusCode == HttpStatusCode.OK).Should().Be(1);
        responses.Count(r => r.StatusCode == HttpStatusCode.Conflict).Should().Be(3);

        ManagedKnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        catalog!.Shortcuts.SelectMany(s => s.Uses)
            .Count(u => u.UsedBy == "My notes tool").Should().Be(1);
    }

    [Fact]
    public async Task Delete_OwnRecord_Returns204AndRemovesIt()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage created = await client.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord());
        ManagedKnownShortcutCatalogDto? catalog =
            await created.Content.ReadFromJsonAsync<ManagedKnownShortcutCatalogDto>();
        Guid recordId = catalog!.Shortcuts.SelectMany(s => s.Uses)
            .Single(u => u.UsedBy == "My notes tool").OwnerRecordId!.Value;

        HttpResponseMessage response = await client.DeleteAsync($"/api/v1/knownshortcuts/{recordId}");

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        ManagedKnownShortcutCatalogDto? after =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        after!.Shortcuts.SelectMany(s => s.Uses).Should().NotContain(u => u.UsedBy == "My notes tool");
    }

    [Fact]
    public async Task Delete_AnotherOwnersRecord_IsNotFound()
    {
        using HttpClient ownerA = CreateAuthed();
        using HttpClient ownerB = CreateAuthed();

        HttpResponseMessage created = await ownerA.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord());
        ManagedKnownShortcutCatalogDto? catalog =
            await created.Content.ReadFromJsonAsync<ManagedKnownShortcutCatalogDto>();
        Guid recordId = catalog!.Shortcuts.SelectMany(s => s.Uses)
            .Single(u => u.UsedBy == "My notes tool").OwnerRecordId!.Value;

        HttpResponseMessage response = await ownerB.DeleteAsync($"/api/v1/knownshortcuts/{recordId}");

        // Not 403: a different status would confirm the record exists.
        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task List_AsAnotherOwner_DoesNotShowTheFirstOwnersRecords()
    {
        using HttpClient ownerA = CreateAuthed();
        using HttpClient ownerB = CreateAuthed();

        await ownerA.PostAsJsonAsync("/api/v1/knownshortcuts", NewRecord(usedBy: "Owner A tool"));

        ManagedKnownShortcutCatalogDto? catalog =
            await ownerB.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");

        catalog!.Shortcuts.SelectMany(s => s.Uses).Should().NotContain(u => u.UsedBy == "Owner A tool");
    }

    [Fact]
    public async Task Ignore_ThenList_StillShowsTheUseAsIgnored()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        ManagedKnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        catalog!.Shortcuts.Single(s => s.Id == ExplorerId).Uses.Single().IsIgnored.Should().BeTrue();
    }

    [Fact]
    public async Task Ignore_ThenReadTheDialogList_DropsTheUse()
    {
        using HttpClient client = CreateAuthed();

        await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        KnownShortcutCatalogDto? dialog =
            await client.GetFromJsonAsync<KnownShortcutCatalogDto>("/api/v1/hotkeys/known-shortcuts");

        dialog!.Shortcuts.Should().NotContain(s => s.Id == ExplorerId);
    }

    [Fact]
    public async Task Ignore_OneBrowserUse_LeavesTheOtherBrowserWarning()
    {
        using HttpClient client = CreateAuthed();

        await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto("browser.new-window", "Chrome"));

        KnownShortcutCatalogDto? dialog =
            await client.GetFromJsonAsync<KnownShortcutCatalogDto>("/api/v1/hotkeys/known-shortcuts");

        dialog!.Shortcuts.Single(s => s.Id == "browser.new-window")
            .Uses.Select(u => u.UsedBy).Should().BeEquivalentTo(["Edge"]);
    }

    [Fact]
    public async Task Restore_MakesTheUseActiveAgain()
    {
        using HttpClient client = CreateAuthed();
        await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/restore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        ManagedKnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        catalog!.Shortcuts.Single(s => s.Id == ExplorerId).Uses.Single().IsIgnored.Should().BeFalse();
    }

    [Fact]
    public async Task Restore_WhenNothingWasIgnored_IsStillNoContent()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/restore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        response.StatusCode.Should().Be(HttpStatusCode.NoContent);
    }

    [Fact]
    public async Task Ignore_UnknownShortcutId_IsNotFound()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore",
            new KnownShortcutUseRefDto("windows.retired-in-a-later-release", "Windows"));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Ignore_UnknownUseOnAKnownShortcut_IsNotFound()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage response = await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Chrome"));

        response.StatusCode.Should().Be(HttpStatusCode.NotFound);
    }

    [Fact]
    public async Task Restore_ByAnotherOwner_LeavesTheFirstOwnersIgnoreInPlace()
    {
        using HttpClient owner = CreateAuthed();
        using HttpClient stranger = CreateAuthed();
        await owner.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        HttpResponseMessage response = await stranger.PostAsJsonAsync(
            "/api/v1/knownshortcuts/restore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        // The stranger owns no ignore row, so restore is a no-op success for them.
        response.StatusCode.Should().Be(HttpStatusCode.NoContent);

        ManagedKnownShortcutCatalogDto? catalog =
            await owner.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        catalog!.Shortcuts.Single(s => s.Id == ExplorerId).Uses.Single().IsIgnored.Should().BeTrue();
    }

    [Fact]
    public async Task Restore_SentConcurrently_AllSucceed()
    {
        using HttpClient client = CreateAuthed();
        await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        // Several requests read the same ignore row, then all try to delete it. Only one delete
        // affects a row; the rest must still report success instead of a 500.
        HttpResponseMessage[] responses = await Task.WhenAll(
            Enumerable.Range(0, 8).Select(_ => client.PostAsJsonAsync(
                "/api/v1/knownshortcuts/restore", new KnownShortcutUseRefDto(ExplorerId, "Windows"))));

        responses.Should().OnlyContain(r => r.StatusCode == HttpStatusCode.NoContent);

        ManagedKnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        catalog!.Shortcuts.Single(s => s.Id == ExplorerId).Uses.Single().IsIgnored.Should().BeFalse();
    }

    [Fact]
    public async Task Ignore_SentConcurrently_AllSucceedAndWriteOneRow()
    {
        using HttpClient client = CreateAuthed();

        HttpResponseMessage[] responses = await Task.WhenAll(
            Enumerable.Range(0, 4).Select(_ => client.PostAsJsonAsync(
                "/api/v1/knownshortcuts/ignore", new KnownShortcutUseRefDto(ExplorerId, "Windows"))));

        responses.Should().OnlyContain(r => r.StatusCode == HttpStatusCode.NoContent);

        // One row: a second would survive the restore below and leave the use silenced.
        await client.PostAsJsonAsync(
            "/api/v1/knownshortcuts/restore", new KnownShortcutUseRefDto(ExplorerId, "Windows"));

        ManagedKnownShortcutCatalogDto? catalog =
            await client.GetFromJsonAsync<ManagedKnownShortcutCatalogDto>("/api/v1/knownshortcuts");
        catalog!.Shortcuts.Single(s => s.Id == ExplorerId).Uses.Single().IsIgnored.Should().BeFalse();
    }
}
