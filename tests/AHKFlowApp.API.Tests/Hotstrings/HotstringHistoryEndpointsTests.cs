using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Extensions.DependencyInjection;
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
    public async Task Revert_SnapshotFailsCurrentRules_Returns400WithTheRuleMessage()
    {
        var oid = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);
        HotstringDto dto = await CreateAsync(client, "he6");

        // Plant an Edit Snapshot whose window context carries a double quote. The rule that
        // forbids it landed after Snapshots started being written, so a stored row can hold one.
        await using (AsyncServiceScope scope = _factory.Services.CreateAsyncScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            HotstringSnapshot bad = new(
                Trigger: "he6", Replacement: "original", Description: null,
                AppliesToAllProfiles: true,
                IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
                ProfileIds: [], CategoryIds: [],
                CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
                ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b");

            db.EntityHistories.Add(EntityHistory.Create(
                oid, TrackedEntityType.Hotstring, dto.Id, version: 1, HistoryChangeType.Edit,
                schemaVersion: 1, JsonSerializer.Serialize(bad), TimeProvider.System));
            await db.SaveChangesAsync();
        }

        HttpResponseMessage revert = await client.PostAsync(
            $"/api/v1/hotstrings/{dto.Id}/history/1/revert", content: null);

        revert.StatusCode.Should().Be(HttpStatusCode.BadRequest);
        string body = await revert.Content.ReadAsStringAsync();
        body.Should().Contain("Value under Window context must not contain double quotes.");
    }

    [Fact]
    public async Task Restore_SnapshotFailsCurrentRules_Returns200AttachedToNoProfile()
    {
        var oid = Guid.NewGuid();
        var id = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);

        // A Delete tombstone, planted directly: the API would refuse to create these values.
        // Two independent failures on purpose — the trailing space in Trigger and the double
        // quote in ContextValue. One failure would still pass if the response carried only the
        // first warning.
        await using (AsyncServiceScope scope = _factory.Services.CreateAsyncScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            HotstringSnapshot bad = new(
                Trigger: "he7 ", Replacement: "text", Description: null,
                AppliesToAllProfiles: true,
                IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
                ProfileIds: [], CategoryIds: [],
                CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
                ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b");

            db.EntityHistories.Add(EntityHistory.Create(
                oid, TrackedEntityType.Hotstring, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(bad), TimeProvider.System));
            await db.SaveChangesAsync();
        }

        HttpResponseMessage restore = await client.PostAsync(
            $"/api/v1/hotstrings/{id}/restore", content: null);

        restore.StatusCode.Should().Be(HttpStatusCode.OK);
        HotstringDto? restored = await restore.Content.ReadFromJsonAsync<HotstringDto>();

        restored!.Id.Should().Be(id);
        restored.AppliesToAllProfiles.Should().BeFalse();
        restored.ProfileIds.Should().BeEmpty();
        restored.BrokenRules.Should().HaveCount(2)
            .And.Contain(new BrokenRuleDto("Trigger", "Trigger must not have leading or trailing whitespace."))
            .And.Contain(new BrokenRuleDto("ContextValue", "Value under Window context must not contain double quotes."));

        // Backlog 175: after the Restore, a read returned restoreWarnings: null. It must name the
        // rules the Restore named (criterion 2).
        HotstringDto? reread = await client.GetFromJsonAsync<HotstringDto>($"/api/v1/hotstrings/{id}");
        reread!.BrokenRules.Should().Equal(restored.BrokenRules!);
    }

    // Backlog 175: after a reload, nothing said why an item reached no script. The list must read
    // the stored row, because its Replacement is cut to 200 characters.
    [Fact]
    public async Task ListAndGet_NameBrokenRules_OnlyForAnItemWithNoProfileThatBreaksThem()
    {
        var oid = Guid.NewGuid();
        using HttpClient client = CreateAuthed(oid);

        await using (AsyncServiceScope scope = _factory.Services.CreateAsyncScope())
        {
            AppDbContext db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Hotstrings.AddRange(
                new HotstringBuilder().WithOwner(oid).WithTrigger("bad")
                    .AppliesToAllProfiles(false)
                    .WithContext(WindowMatchType.TitleContains, "a \" b").Build(),
                new HotstringBuilder().WithOwner(oid).WithTrigger("long")
                    .AppliesToAllProfiles(false)
                    .WithDelivery(HotstringDelivery.Type)
                    .WithReplacement(new string('x', 4001)).Build(),
                new HotstringBuilder().WithOwner(oid).WithTrigger("lost")
                    .AppliesToAllProfiles(false).Build(),
                new HotstringBuilder().WithOwner(oid).WithTrigger("scoped")
                    .AppliesToAllProfiles(true)
                    .WithContext(WindowMatchType.TitleContains, "a \" b").Build());
            await db.SaveChangesAsync();
        }

        PagedList<HotstringDto>? page = await client.GetFromJsonAsync<PagedList<HotstringDto>>("/api/v1/hotstrings");
        var byTrigger = page!.Items.ToDictionary(h => h.Trigger);

        byTrigger["bad"].BrokenRules.Should().Equal(
            new BrokenRuleDto("ContextValue", "Value under Window context must not contain double quotes."));
        byTrigger["long"].BrokenRules.Should().Equal(                    // Review Focus 2
            new BrokenRuleDto("Replacement", "Replacement must be 4000 characters or fewer."));
        byTrigger["lost"].BrokenRules.Should().BeNull();
        byTrigger["scoped"].BrokenRules.Should().BeNull();              // Review Focus 3

        foreach (HotstringDto listed in byTrigger.Values)
        {
            HotstringDto? single = await client.GetFromJsonAsync<HotstringDto>($"/api/v1/hotstrings/{listed.Id}");
            if (listed.BrokenRules is null)
                single!.BrokenRules.Should().BeNull();
            else
                single!.BrokenRules.Should().Equal(listed.BrokenRules);
        }
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
