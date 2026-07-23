using System.Text.Json;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class EntityHistoryRecorderTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task RecordHotstringAsync_FirstRecord_WritesVersion1WithFullSnapshot()
    {
        var owner = Guid.NewGuid();
        var profileId = Guid.NewGuid();
        var categoryId = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("rec1").WithReplacement("body")
            .WithProfiles(profileId).WithCategory(categoryId)
            .WithDelivery(HotstringDelivery.ClipboardPaste)
            .Build();

        await using AppDbContext db = fx.CreateContext();
        db.Hotstrings.Add(entity);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);

        entry.OwnerOid.Should().Be(owner);
        entry.EntityType.Should().Be(TrackedEntityType.Hotstring);
        entry.EntityId.Should().Be(entity.Id);
        entry.Version.Should().Be(1);
        entry.ChangeType.Should().Be(HistoryChangeType.Edit);
        entry.SchemaVersion.Should().Be(EntityHistoryRecorder.CurrentSchemaVersion);

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(entry.SnapshotJson);
        snapshot!.Trigger.Should().Be("rec1");
        snapshot.Replacement.Should().Be("body");
        snapshot.AppliesToAllProfiles.Should().BeFalse();
        snapshot.ProfileIds.Should().ContainSingle().Which.Should().Be(profileId);
        snapshot.CategoryIds.Should().ContainSingle().Which.Should().Be(categoryId);
        snapshot.Delivery.Should().Be(HotstringDelivery.ClipboardPaste);
    }

    [Fact]
    public async Task RecordHotstringAsync_SecondRecord_IncrementsVersion()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rec2").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            EntityHistoryRecorder seedRecorder = new(seed, TimeProvider.System);
            await seedRecorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Hotstring reloaded = await db.Hotstrings.SingleAsync(h => h.Id == entity.Id);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotstringAsync(reloaded, HistoryChangeType.Edit, default);

        entry.Version.Should().Be(2);
    }

    [Fact]
    public async Task RecordHotstringAsync_SameEntityIdForDifferentOwner_StartsAtVersion1()
    {
        var owner = Guid.NewGuid();
        var otherOwner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rec2-owner").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            seed.EntityHistories.Add(EntityHistory.Create(
                otherOwner, TrackedEntityType.Hotstring, entity.Id, 7,
                HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Hotstring reloaded = await db.Hotstrings.SingleAsync(h => h.Id == entity.Id);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotstringAsync(reloaded, HistoryChangeType.Edit, default);

        entry.Version.Should().Be(1);
    }

    [Fact]
    public async Task RecordHotstringAsync_At50Rows_PrunesOldestSoCapHolds()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rec3").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            for (int version = 1; version <= 50; version++)
            {
                seed.EntityHistories.Add(EntityHistory.Create(
                    owner, TrackedEntityType.Hotstring, entity.Id, version,
                    HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
            }

            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Hotstring reloaded = await db.Hotstrings.SingleAsync(h => h.Id == entity.Id);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        await recorder.RecordHotstringAsync(reloaded, HistoryChangeType.Edit, default);
        await db.SaveChangesAsync();

        List<int> versions = await db.EntityHistories
            .Where(h => h.EntityId == entity.Id)
            .Select(h => h.Version)
            .OrderBy(v => v)
            .ToListAsync();
        versions.Should().HaveCount(50);
        versions.First().Should().Be(2);
        versions.Last().Should().Be(51);
    }

    [Fact]
    public async Task RecordHotkeyAsync_WritesTypedActionColumnsAndNoLegacyPair()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithRun("https://github.com", RunTargetKind.Url).Build();

        await using AppDbContext db = fx.CreateContext();
        db.Hotkeys.Add(entity);
        EntityHistoryRecorder recorder = new(db, TimeProvider.System);

        EntityHistory entry = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Delete, default);

        entry.EntityType.Should().Be(TrackedEntityType.Hotkey);
        entry.ChangeType.Should().Be(HistoryChangeType.Delete);
        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(entry.SnapshotJson);
        snapshot!.Key.Should().Be(entity.Key);
        snapshot.ActionKind.Should().Be(HotkeyActionKind.Run);
        snapshot.RunTarget.Should().Be("https://github.com");
        snapshot.RunTargetKind.Should().Be(RunTargetKind.Url);
        snapshot.Action.Should().BeNull();
        snapshot.Parameters.Should().BeNull();
        snapshot.CreatedAt.Should().Be(entity.CreatedAt);
    }

    [Fact]
    public async Task UniqueIndex_DuplicateVersionForSameEntity_Throws()
    {
        var owner = Guid.NewGuid();
        var entityId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        db.EntityHistories.Add(EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
        await db.SaveChangesAsync();

        db.EntityHistories.Add(EntityHistory.Create(
            owner, TrackedEntityType.Hotstring, entityId, 1, HistoryChangeType.Edit, 1, "{}", TimeProvider.System));
        Func<Task> act = async () => await db.SaveChangesAsync();

        await act.Should().ThrowAsync<DbUpdateException>();
    }
}
