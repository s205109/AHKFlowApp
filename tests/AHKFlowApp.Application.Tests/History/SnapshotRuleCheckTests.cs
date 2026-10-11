using System.Text.Json;
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class SnapshotRuleCheckTests(HistoryDbFixture fx)
{
    // A window context carrying a double quote. The rule forbidding it landed on 2026-07-11,
    // after Snapshots started being written on 2026-07-02, so a stored row can hold one.
    private static HotstringSnapshot BadContextSnapshot(Guid[] profileIds, bool appliesToAll) =>
        new(
            Trigger: "bad1", Replacement: "text", Description: null,
            AppliesToAllProfiles: appliesToAll,
            IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
            ProfileIds: profileIds, CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b");

    // Key validation against the closed registry landed on 2026-07-21. A Snapshot written
    // before that can hold a name the registry refuses today.
    private static HotkeySnapshot BadKeySnapshot() =>
        new(
            Description: "Open Notepad", Key: "NotAKeyName",
            Ctrl: true, Alt: false, Shift: false, Win: false,
            AppliesToAllProfiles: true, ProfileIds: [], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            ActionKind: HotkeyActionKind.Run, RunTarget: "notepad.exe",
            RunTargetKind: RunTargetKind.Application);

    [Fact]
    public async Task RevertHotstring_SnapshotFailsCurrentRules_ReturnsInvalidAndLeavesItemUnchanged()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("good1").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entity.Id, version: 1, HistoryChangeType.Edit,
                schemaVersion: 1, JsonSerializer.Serialize(BadContextSnapshot([], appliesToAll: true)),
                TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(
            new RevertHotstringCommand(entity.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Invalid);
        result.ValidationErrors.Select(e => e.ErrorMessage).Should()
            .Contain("ContextValue must not contain double-quote characters.");

        Hotstring after = await db.Hotstrings.AsNoTracking().SingleAsync(h => h.Id == entity.Id);
        after.Trigger.Should().Be("good1");
        after.ContextValue.Should().BeNull();
    }

    // Review Focus 5: a refused Revert must stage no history change at all.
    //
    // Counting rows does NOT test this, and an earlier draft of this plan got it wrong. The
    // recorder only stages its work — it calls AddRange and RemoveRange and never saves, and the
    // save happens later in the handler. So a row count reads the same whether the check runs
    // above the recorder or below it, as long as the handler returns before saving. The evidence
    // of a mis-ordered check lives in the change tracker, so that is what this asserts.
    [Theory]
    [InlineData(false)]  // under the retention limit: the recorder would only stage an add
    [InlineData(true)]   // at the retention limit: the recorder would also stage a delete
    public async Task RevertHotstring_SnapshotFailsCurrentRules_StagesNoHistoryChange(bool atRetentionLimit)
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("good2").Build();
        string badJson = JsonSerializer.Serialize(BadContextSnapshot([], appliesToAll: true));

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);

            // Read the limit from the recorder rather than hard-coding it, so a retention change
            // cannot quietly turn this case back into the under-the-limit one. The constant is
            // internal and AHKFlowApp.Application.Tests already has InternalsVisibleTo.
            int versionsToSeed = atRetentionLimit ? EntityHistoryRecorder.MaxVersionsPerItem : 1;
            for (int version = 1; version <= versionsToSeed; version++)
            {
                seed.EntityHistories.Add(EntityHistory.Create(
                    owner, TrackedEntityType.Hotstring, entity.Id, version, HistoryChangeType.Edit,
                    schemaVersion: 1, badJson, TimeProvider.System));
            }

            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(
            new RevertHotstringCommand(entity.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Invalid);

        // The assertion that actually fails when the check moves below the recorder.
        db.ChangeTracker.Entries<EntityHistory>()
            .Where(e => e.State is EntityState.Added or EntityState.Deleted)
            .Should().BeEmpty("a refused Revert must stage no history add and no history delete");

        // And nothing reaches the database either, even if something else saves this context.
        await db.SaveChangesAsync();
        int versions = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versions.Should().Be(
            atRetentionLimit ? EntityHistoryRecorder.MaxVersionsPerItem : 1,
            "a refused Revert changes the timeline in no way");
    }

    [Fact]
    public async Task RevertHotkey_SnapshotKeyNotInRegistry_ReturnsInvalidAndLeavesItemUnchanged()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("Open Notepad").WithKey("n").WithCtrl()
            .WithRun("notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotkey, entity.Id, version: 1, HistoryChangeType.Edit,
                schemaVersion: 1, JsonSerializer.Serialize(BadKeySnapshot()), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(
            new RevertHotkeyCommand(entity.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Invalid);
        Hotkey after = await db.Hotkeys.AsNoTracking().SingleAsync(h => h.Id == entity.Id);
        after.Key.Should().Be("n");
    }

    // Review Focus 5, hotkey side. The test above does not cover ordering: both of its
    // assertions hold whether the check runs above the recorder or below it, because the
    // recorder only stages. The hotkey handler needs its own staging assertion.
    [Theory]
    [InlineData(false)]  // under the retention limit: the recorder would only stage an add
    [InlineData(true)]   // at the retention limit: the recorder would also stage a delete
    public async Task RevertHotkey_SnapshotFailsCurrentRules_StagesNoHistoryChange(bool atRetentionLimit)
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("Open Notepad").WithKey("n").WithCtrl()
            .WithRun("notepad.exe")
            .Build();
        string badJson = JsonSerializer.Serialize(BadKeySnapshot());

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);

            int versionsToSeed = atRetentionLimit ? EntityHistoryRecorder.MaxVersionsPerItem : 1;
            for (int version = 1; version <= versionsToSeed; version++)
            {
                seed.EntityHistories.Add(EntityHistory.Create(
                    owner, TrackedEntityType.Hotkey, entity.Id, version, HistoryChangeType.Edit,
                    schemaVersion: 1, badJson, TimeProvider.System));
            }

            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(
            new RevertHotkeyCommand(entity.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Invalid);

        // EntityHistory rows are typed by TrackedEntityType, so this query needs no change from
        // the hotstring theory: it already asks about EntityHistory entries of any entity type.
        db.ChangeTracker.Entries<EntityHistory>()
            .Where(e => e.State is EntityState.Added or EntityState.Deleted)
            .Should().BeEmpty("a refused Revert must stage no history add and no history delete");

        await db.SaveChangesAsync();
        int versions = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versions.Should().Be(
            atRetentionLimit ? EntityHistoryRecorder.MaxVersionsPerItem : 1,
            "a refused Revert changes the timeline in no way");
    }

    [Fact]
    public async Task RestoreHotstring_SnapshotFailsCurrentRules_CreatesItemAttachedToNoProfile()
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(BadContextSnapshot([], appliesToAll: true)),
                TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
        result.Value.RestoreWarnings.Should()
            .Contain("ContextValue must not contain double-quote characters.");

        Hotstring stored = await db.Hotstrings.AsNoTracking().SingleAsync(h => h.Id == id);
        stored.AppliesToAllProfiles.Should().BeFalse();
        (await db.HotstringProfiles.CountAsync(j => j.HotstringId == id)).Should().Be(0);
    }

    // Review Focus 4: D5 only moves AppliesToAllProfiles when the Snapshot said true. A Snapshot
    // that named Profiles explicitly takes the other branch and must still end up detached.
    [Fact]
    public async Task RestoreHotstring_FailingSnapshotWithExplicitProfiles_DropsTheLinks()
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1,
                JsonSerializer.Serialize(BadContextSnapshot([profile.Id], appliesToAll: false)),
                TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();
        result.Value.RestoreWarnings.Should().NotBeNullOrEmpty();
        (await db.HotstringProfiles.CountAsync(j => j.HotstringId == id)).Should().Be(0);
    }

    // Review Focus 3: a Snapshot whose Profiles were all deleted already restores with none.
    // That is a success with no warnings, and must stay one.
    [Fact]
    public async Task RestoreHotstring_ValidSnapshotWhoseProfilesAreGone_SucceedsWithNoWarnings()
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();
        var deletedProfileId = Guid.NewGuid();

        HotstringSnapshot good = new(
            Trigger: "ok1", Replacement: "fine", Description: null,
            AppliesToAllProfiles: false,
            IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
            ProfileIds: [deletedProfileId], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(good), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();
        result.Value.RestoreWarnings.Should().BeNullOrEmpty();
        result.Value.AppliesToAllProfiles.Should().BeFalse("the snapshot said false and it passed the rules");
    }

    [Fact]
    public async Task RestoreHotkey_SnapshotKeyNotInRegistry_CreatesItemAttachedToNoProfile()
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotkey, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(BadKeySnapshot()), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RestoreHotkeyCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
        result.Value.RestoreWarnings.Should().NotBeNullOrEmpty();
        (await db.HotkeyProfiles.CountAsync(j => j.HotkeyId == id)).Should().Be(0);
    }
}
