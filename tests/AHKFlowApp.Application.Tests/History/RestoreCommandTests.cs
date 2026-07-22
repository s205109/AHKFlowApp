using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class RestoreCommandTests(HistoryDbFixture fx)
{
    private async Task DeleteHotstringViaHandlerAsync(Guid owner, Guid id)
    {
        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.ExecuteAsync(new DeleteHotstringCommand(id), default);
        result.IsSuccess.Should().BeTrue();
    }

    private async Task DeleteHotkeyViaHandlerAsync(Guid owner, Guid id)
    {
        await using AppDbContext db = fx.CreateContext();
        DeleteHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.ExecuteAsync(new DeleteHotkeyCommand(id), default);
        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task RestoreHotstring_ReinsertsWithOriginalIdCreatedAtAndLinks()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("rs1")
            .WithProfiles(profile.Id)
            .WithCategory(category.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Categories.Add(category);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotstringViaHandlerAsync(owner, entity.Id);

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.CreatedAt.Should().Be(entity.CreatedAt);
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);
        (await db.Hotstrings.AnyAsync(h => h.Id == entity.Id)).Should().BeTrue();
        List<HistoryChangeType> changes = await db.EntityHistories
            .Where(h => h.EntityId == entity.Id)
            .OrderBy(h => h.Version)
            .Select(h => h.ChangeType)
            .ToListAsync();
        changes.Should().Equal(HistoryChangeType.Delete, HistoryChangeType.Restore);
    }

    [Fact]
    public async Task RestoreHotstring_LegacyScriptSnapshot_ConvertsToRaw()
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();

        // Hand-craft a pre-Raw Delete tombstone carrying a legacy Kind=Script snapshot.
#pragma warning disable CS0618 // Simulating a stored legacy snapshot.
        HotstringSnapshot legacy = new(
            Trigger: "~ver", Replacement: "MsgBox A_AhkVersion", Description: null,
            AppliesToAllProfiles: true, IsEndingCharacterRequired: false, IsTriggerInsideWord: false,
            ProfileIds: [], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            Kind: HotstringKind.Script);
#pragma warning restore CS0618

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, System.Text.Json.JsonSerializer.Serialize(legacy), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Kind.Should().Be(HotstringKind.Raw);
        result.Value.Trigger.Should().Be("~ver");
        result.Value.Replacement.Should().Be(":*:~ver::\n{\nMsgBox A_AhkVersion\n}");
    }

    [Fact]
    public async Task RestoreHotstring_TriggerNowTaken_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rs2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotstringViaHandlerAsync(owner, entity.Id);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder().WithOwner(owner).WithTrigger("rs2").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(entity.Id), default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task RestoreHotstring_NoTombstone_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler =
            new(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task RestoreHotstring_SnapshotProfileDeleted_RestoresWithZeroLinks()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("rs3")
            .WithProfiles(profile.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotstringViaHandlerAsync(owner, entity.Id);

        await using (AppDbContext del = fx.CreateContext())
        {
            del.Profiles.Remove(await del.Profiles.SingleAsync(p => p.Id == profile.Id));
            await del.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RestoreHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task RestoreHotkey_ReinsertsWithOriginalIdCreatedAtAndLinks()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner)
            .WithKey("f14")
            .WithProfiles(profile.Id)
            .WithCategory(category.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Categories.Add(category);
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotkeyViaHandlerAsync(owner, entity.Id);

        await using AppDbContext db = fx.CreateContext();
        RestoreHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RestoreHotkeyCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.CreatedAt.Should().Be(entity.CreatedAt);
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);
        List<HistoryChangeType> changes = await db.EntityHistories
            .Where(h => h.EntityId == entity.Id)
            .OrderBy(h => h.Version)
            .Select(h => h.ChangeType)
            .ToListAsync();
        changes.Should().Equal(HistoryChangeType.Delete, HistoryChangeType.Restore);
    }

    [Theory]
    [MemberData(nameof(TypedActions))]
    public async Task RestoreHotkey_TypedTombstone_RestoresTypedActionPayload(CreateHotkeyDto original)
    {
        var owner = Guid.NewGuid();

        Guid id;
        await using (AppDbContext create = fx.CreateContext())
        {
            CreateHotkeyCommandHandler handler = new(create, CurrentUserHelper.For(owner), TimeProvider.System);
            Result<HotkeyDto> created = await handler.ExecuteAsync(new CreateHotkeyCommand(original), default);
            created.IsSuccess.Should().BeTrue();
            id = created.Value.Id;
        }

        await DeleteHotkeyViaHandlerAsync(owner, id);

        await using AppDbContext db = fx.CreateContext();
        RestoreHotkeyCommandHandler restoreHandler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await restoreHandler.ExecuteAsync(new RestoreHotkeyCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        HotkeyDto restored = result.Value;
        restored.ActionKind.Should().Be(original.ActionKind);
        restored.Text.Should().Be(original.Text);
        restored.SendKeysContent.Should().Be(original.SendKeysContent);
        restored.RunTarget.Should().Be(original.RunTarget);
        restored.RunTargetKind.Should().Be(original.RunTargetKind);
        restored.WindowOp.Should().Be(original.WindowOp);
        restored.RemapDest.Should().Be(original.RemapDest);
        restored.Body.Should().Be(original.Body);

        Hotkey persisted = await db.Hotkeys.AsNoTracking().SingleAsync(h => h.Id == id);
        persisted.ActionKind.Should().Be(original.ActionKind);
    }

    [Fact]
    public async Task RestoreHotkey_LegacyShapedTombstone_ConvertsThroughLegacyRules()
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();

        // A pre-W1 tombstone: only the legacy pair was ever written to the snapshot JSON.
        string legacyJson = System.Text.Json.JsonSerializer.Serialize(new
        {
            Description = "legacy run",
            Key = "f15",
            Ctrl = false,
            Alt = false,
            Shift = false,
            Win = false,
            Action = HotkeyAction.Run,
            Parameters = "notepad.exe",
            AppliesToAllProfiles = true,
            ProfileIds = Array.Empty<Guid>(),
            CategoryIds = Array.Empty<Guid>(),
            CreatedAt = DateTimeOffset.UnixEpoch,
            UpdatedAt = DateTimeOffset.UnixEpoch,
        });

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotkey, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, legacyJson, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RestoreHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RestoreHotkeyCommand(id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("legacy run");
        result.Value.ActionKind.Should().Be(HotkeyActionKind.Run);
        result.Value.RunTarget.Should().Be("notepad.exe");
        result.Value.RunTargetKind.Should().Be(RunTargetKind.Application);
    }

    /// <summary>One create payload per action kind — the restore round trip must return each verbatim.</summary>
    public static TheoryData<CreateHotkeyDto> TypedActions() =>
    [
        new CreateHotkeyDto("run", "f2", HotkeyActionKind.Run,
            RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application, AppliesToAllProfiles: true),
        new CreateHotkeyDto("text", "f3", HotkeyActionKind.SendText,
            Text: "hello world", AppliesToAllProfiles: true),
        new CreateHotkeyDto("keys", "f4", HotkeyActionKind.SendKeys,
            SendKeysContent: "^v", AppliesToAllProfiles: true),
        new CreateHotkeyDto("window", "f5", HotkeyActionKind.Window,
            WindowOp: WindowOp.Close, AppliesToAllProfiles: true),
        new CreateHotkeyDto("remap", "a", HotkeyActionKind.Remap,
            RemapDest: "b", AppliesToAllProfiles: true),
        new CreateHotkeyDto("raw", "f6", HotkeyActionKind.Raw,
            Body: "MsgBox \"hi\"", AppliesToAllProfiles: true),
        new CreateHotkeyDto("disable", "f7", HotkeyActionKind.Disable, AppliesToAllProfiles: true),
    ];
}
