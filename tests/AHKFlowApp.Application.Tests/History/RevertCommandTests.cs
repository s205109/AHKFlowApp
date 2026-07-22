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
public sealed class RevertCommandTests(HistoryDbFixture fx)
{
    private async Task UpdateHotstringViaHandlerAsync(Guid owner, Guid id, UpdateHotstringDto dto)
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        Result<HotstringDto> result = await handler.ExecuteAsync(new UpdateHotstringCommand(id, dto), default);
        result.IsSuccess.Should().BeTrue();
    }

    private async Task UpdateHotkeyViaHandlerAsync(Guid owner, Guid id, UpdateHotkeyDto dto)
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        Result<HotkeyDto> result = await handler.ExecuteAsync(new UpdateHotkeyCommand(id, dto), default);
        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task RevertHotstring_RestoresFieldsAndLinks_AndWritesNewBeforeImage()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("rv1")
            .WithReplacement("original")
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

        await UpdateHotstringViaHandlerAsync(owner, entity.Id,
            new UpdateHotstringDto("rv1", "changed", null, true, true, true, null));

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Replacement.Should().Be("original");
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);

        int versionCount = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versionCount.Should().Be(2);
    }

    [Fact]
    public async Task RevertHotstring_LegacyScriptSnapshot_ConvertsToRaw()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("~ver").WithReplacement("current").Build();

        // A version-1 history row carrying a legacy Kind=Script snapshot to revert back to.
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
            seed.Hotstrings.Add(entity);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, entity.Id, version: 1, HistoryChangeType.Edit,
                schemaVersion: 1, System.Text.Json.JsonSerializer.Serialize(legacy), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Kind.Should().Be(HotstringKind.Raw);
        result.Value.Replacement.Should().Be(":*:~ver::\n{\nMsgBox A_AhkVersion\n}");
    }

    [Fact]
    public async Task RevertHotstring_SnapshotProfileDeleted_DropsMissingLinkSilently()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("rv2")
            .WithProfiles(profile.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateHotstringViaHandlerAsync(owner, entity.Id,
            new UpdateHotstringDto("rv2", "by the way", null, true, true, true, null));

        await using (AppDbContext del = fx.CreateContext())
        {
            del.Profiles.Remove(await del.Profiles.SingleAsync(p => p.Id == profile.Id));
            await del.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task RevertHotstring_TriggerNowTakenByAnotherHotstring_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotstring victim = new HotstringBuilder().WithOwner(owner).WithTrigger("rv3-old").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(victim);
            await seed.SaveChangesAsync();
        }

        await UpdateHotstringViaHandlerAsync(owner, victim.Id,
            new UpdateHotstringDto("rv3-new", "by the way", null, true, true, true, null));

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder().WithOwner(owner).WithTrigger("rv3-old").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RevertHotstringCommand(victim.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task RevertHotstring_UnknownVersion_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rv4").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.ExecuteAsync(new RevertHotstringCommand(entity.Id, 9), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    private async Task<Guid> CreateHotkeyViaHandlerAsync(Guid owner, CreateHotkeyDto dto)
    {
        await using AppDbContext db = fx.CreateContext();
        CreateHotkeyCommandHandler handler = new(db, CurrentUserHelper.For(owner), TimeProvider.System);
        Result<HotkeyDto> result = await handler.ExecuteAsync(new CreateHotkeyCommand(dto), default);
        result.IsSuccess.Should().BeTrue();
        return result.Value.Id;
    }

    [Fact]
    public async Task RevertHotkey_RestoresFieldsAndLinks_AndWritesNewBeforeImage()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner)
            .WithDescription("original")
            .WithKey("f12")
            .WithCtrl()
            .WithSendText("payload-v1")
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

        await UpdateHotkeyViaHandlerAsync(owner, entity.Id,
            new UpdateHotkeyDto("changed", "f11", HotkeyActionKind.SendText,
                Ctrl: false, Alt: true, Shift: false, Win: false,
                Text: "payload", SendKeysContent: null, RunTarget: null, RunTargetKind: null,
                WindowOp: null, RemapDest: null, Body: null,
                ProfileIds: null, AppliesToAllProfiles: true));

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RevertHotkeyCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("original");
        result.Value.Key.Should().Be("f12");
        result.Value.Ctrl.Should().BeTrue();
        result.Value.Alt.Should().BeFalse();
        result.Value.ActionKind.Should().Be(HotkeyActionKind.SendText);
        result.Value.Text.Should().Be("payload-v1");
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);

        int versionCount = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versionCount.Should().Be(2);
    }

    [Theory]
    [MemberData(nameof(TypedActions))]
    public async Task RevertHotkey_TypedSnapshot_RestoresTypedActionPayload(CreateHotkeyDto original)
    {
        var owner = Guid.NewGuid();
        string key = original.Key;
        Guid id = await CreateHotkeyViaHandlerAsync(owner, original);

        await UpdateHotkeyViaHandlerAsync(owner, id,
            new UpdateHotkeyDto("overwritten", key, HotkeyActionKind.Disable,
                Ctrl: false, Alt: false, Shift: false, Win: false,
                Text: null, SendKeysContent: null, RunTarget: null, RunTargetKind: null,
                WindowOp: null, RemapDest: null, Body: null,
                ProfileIds: null, AppliesToAllProfiles: true));

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RevertHotkeyCommand(id, 1), default);

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
    }

    [Fact]
    public async Task RevertHotkey_LegacyShapedSnapshot_ConvertsThroughLegacyRules()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey("f7").WithRun("chrome.exe").Build();

        // A pre-W1 history row: only the legacy pair was ever written to the snapshot JSON.
        string legacyJson = System.Text.Json.JsonSerializer.Serialize(new
        {
            Description = "legacy",
            Key = "f7",
            Ctrl = false,
            Alt = false,
            Shift = false,
            Win = false,
            Action = HotkeyAction.Run,
            Parameters = "https://github.com",
            AppliesToAllProfiles = true,
            ProfileIds = Array.Empty<Guid>(),
            CategoryIds = Array.Empty<Guid>(),
            CreatedAt = DateTimeOffset.UnixEpoch,
            UpdatedAt = DateTimeOffset.UnixEpoch,
        });

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotkey, entity.Id, version: 1, HistoryChangeType.Edit,
                schemaVersion: 1, legacyJson, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RevertHotkeyCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("legacy");
        result.Value.ActionKind.Should().Be(HotkeyActionKind.Run);
        result.Value.RunTarget.Should().Be("https://github.com");
        result.Value.RunTargetKind.Should().Be(RunTargetKind.Url);
    }

    /// <summary>One create payload per action kind — the revert round trip must return each verbatim.</summary>
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
    ];
}
