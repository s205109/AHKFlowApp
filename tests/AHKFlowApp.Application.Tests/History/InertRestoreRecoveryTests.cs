using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Behaviors;
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Downloads;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using AHKFlowApp.TestUtilities.Fixtures;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

/// <summary>
/// The whole route an Owner walks after a Restore fails the current rules: the Item comes back
/// applying to no profile, no Profile script contains it, the Owner repairs it and gives it a
/// Profile, and then the script contains it. Asserting only the first step would pass while the
/// Owner is still stuck.
/// <para>
/// The repair step goes through <c>ValidatingUseCase</c>, not straight to the Update handler. The
/// Update rules live in that decorator, so a direct handler call would prove nothing about whether
/// the Owner can actually save the repair.
/// </para>
/// </summary>
[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class InertRestoreRecoveryTests(HistoryDbFixture fx)
{
    private static AhkScriptGenerator CreateGenerator()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    private static async Task<string> GenerateAsync(AppDbContext ctx, Guid owner, Guid profileId)
    {
        ICurrentUser cu = Substitute.For<ICurrentUser>();
        cu.Oid.Returns(owner);
        GenerateProfileScriptQueryHandler sut = new(new ProfileScriptLoader(ctx), cu, CreateGenerator());

        Result<ProfileScript> script = await sut.ExecuteAsync(
            new GenerateProfileScriptQuery(profileId), CancellationToken.None);

        script.IsSuccess.Should().BeTrue();
        return script.Value.Content;
    }

    [Theory]
    [InlineData(true)]   // the Snapshot applied to all profiles
    [InlineData(false)]  // the Snapshot named its profiles
    public async Task FailingRestore_IsAbsentFromTheScriptUntilRepaired(bool snapshotAppliedToAll)
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();
        Profile work = new ProfileBuilder().WithOwner(owner).WithName($"Work-{Guid.NewGuid():N}").Build();

        // 1. A Delete tombstone whose window context carries a double quote. The rule forbidding
        //    that landed after Snapshots started being written, so a stored row can hold one.
        HotstringSnapshot bad = new(
            Trigger: "recov", Replacement: "recovered text", Description: null,
            AppliesToAllProfiles: snapshotAppliedToAll,
            IsEndingCharacterRequired: true, IsTriggerInsideWord: false,
            ProfileIds: snapshotAppliedToAll ? [] : [work.Id], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b");

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(work);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotstring, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(bad), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        // 2. Restore it. It comes back, applying to no profile, and says which rule failed.
        await using (AppDbContext db = fx.CreateContext())
        {
            RestoreHotstringCommandHandler restore = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));

            Result<HotstringDto> restored = await restore.ExecuteAsync(
                new RestoreHotstringCommand(id), default);

            restored.IsSuccess.Should().BeTrue();
            restored.Value.ProfileIds.Should().BeEmpty();
            restored.Value.AppliesToAllProfiles.Should().BeFalse();
            restored.Value.RestoreWarnings.Should().NotBeNullOrEmpty();
        }

        // 3. The Profile script does not contain it.
        await using (AppDbContext db = fx.CreateContext())
        {
            string before = await GenerateAsync(db, owner, work.Id);
            before.Should().NotContain("recov",
                "an item applying to no profile is excluded by the script loader's predicate");
        }

        // 4. The Owner repairs the bad value and gives it a Profile.
        //
        // This goes through ValidatingUseCase, not straight to the handler. The handler alone
        // never sees the Update rules — they run in the decorator — so a direct handler call
        // would pass even if ordinary Update rejected the repair, and the Owner would still be
        // stuck. Building the decorator by hand keeps the test in this project and still
        // exercises the real validator.
        await using (AppDbContext db = fx.CreateContext())
        {
            UpdateHotstringCommandHandler handler = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));
            ValidatingUseCase<UpdateHotstringCommand, Result<HotstringDto>> update =
                new([new UpdateHotstringCommandValidator()], handler);

            UpdateHotstringDto stillBad = new(
                Trigger: "recov",
                Replacement: "recovered text",
                ProfileIds: [work.Id],
                AppliesToAllProfiles: false,
                IsEndingCharacterRequired: true,
                IsTriggerInsideWord: false,
                Description: null,
                ContextMatchType: WindowMatchType.TitleContains,
                ContextValue: "a \" b");

            // First prove the unrepaired value is really rejected. Without this the next
            // assertion proves nothing: a validator that accepted everything would also pass.
            // ValidatingUseCase throws, and GlobalExceptionMiddleware turns that into a 400.
            await FluentActions
                .Awaiting(() => update.ExecuteAsync(new UpdateHotstringCommand(id, stillBad), default))
                .Should().ThrowAsync<FluentValidation.ValidationException>(
                    "the Owner cannot save the Item until the bad value is gone");

            UpdateHotstringDto repair = stillBad with { ContextValue = "a b" };

            Result<HotstringDto> repaired = await update.ExecuteAsync(
                new UpdateHotstringCommand(id, repair), default);

            repaired.IsSuccess.Should().BeTrue(
                "the edit dialog is the repair route, so Update must accept the fixed values");
            repaired.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(work.Id);
        }

        // 5. The Profile script now contains it.
        await using (AppDbContext db = fx.CreateContext())
        {
            string after = await GenerateAsync(db, owner, work.Id);
            after.Should().Contain("recov");
        }
    }

    [Theory]
    [InlineData(true)]   // the Snapshot applied to all profiles
    [InlineData(false)]  // the Snapshot named its profiles
    public async Task FailingHotkeyRestore_IsAbsentFromTheScriptUntilRepaired(bool snapshotAppliedToAll)
    {
        var owner = Guid.NewGuid();
        var id = Guid.NewGuid();
        Profile work = new ProfileBuilder().WithOwner(owner).WithName($"Work-{Guid.NewGuid():N}").Build();

        // 1. A Delete tombstone whose window context carries a double quote, as above. The hotkey
        //    runs a uniquely named target, so the script assertions below cannot match anything
        //    else the fixture holds.
        HotkeySnapshot bad = new(
            Description: "Recover me", Key: "n",
            Ctrl: true, Alt: false, Shift: false, Win: false,
            AppliesToAllProfiles: snapshotAppliedToAll,
            ProfileIds: snapshotAppliedToAll ? [] : [work.Id], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch,
            ActionKind: HotkeyActionKind.Run, RunTarget: "recovhk.exe",
            RunTargetKind: RunTargetKind.Application,
            ContextMatchType: WindowMatchType.TitleContains, ContextValue: "a \" b");

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(work);
            seed.EntityHistories.Add(EntityHistory.Create(
                owner, TrackedEntityType.Hotkey, id, version: 1, HistoryChangeType.Delete,
                schemaVersion: 1, JsonSerializer.Serialize(bad), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        // 2. Restore it. It comes back, applying to no profile, and says which rule failed.
        await using (AppDbContext db = fx.CreateContext())
        {
            RestoreHotkeyCommandHandler restore = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));

            Result<HotkeyDto> restored = await restore.ExecuteAsync(
                new RestoreHotkeyCommand(id), default);

            restored.IsSuccess.Should().BeTrue();
            restored.Value.ProfileIds.Should().BeEmpty();
            restored.Value.AppliesToAllProfiles.Should().BeFalse();
            restored.Value.RestoreWarnings.Should().NotBeNullOrEmpty();
        }

        // 3. The Profile script does not contain it.
        await using (AppDbContext db = fx.CreateContext())
        {
            string before = await GenerateAsync(db, owner, work.Id);
            before.Should().NotContain("recovhk",
                "an item applying to no profile is excluded by the script loader's predicate");
        }

        // 4. The Owner repairs the bad value and gives it a Profile, through ValidatingUseCase for
        //    the same reason the hotstring case does: the Update rules live in the decorator.
        await using (AppDbContext db = fx.CreateContext())
        {
            UpdateHotkeyCommandHandler handler = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System,
                new EntityHistoryRecorder(db, TimeProvider.System));
            ValidatingUseCase<UpdateHotkeyCommand, Result<HotkeyDto>> update =
                new([new UpdateHotkeyCommandValidator()], handler);

            UpdateHotkeyDto stillBad = new(
                Description: "Recover me",
                Key: "n",
                ActionKind: HotkeyActionKind.Run,
                Ctrl: true, Alt: false, Shift: false, Win: false,
                Text: null,
                SendKeysContent: null,
                RunTarget: "recovhk.exe",
                RunTargetKind: RunTargetKind.Application,
                WindowOp: null,
                RemapDest: null,
                Body: null,
                ProfileIds: [work.Id],
                AppliesToAllProfiles: false,
                ContextMatchType: WindowMatchType.TitleContains,
                ContextValue: "a \" b");

            // Prove the unrepaired value is really rejected first, or the next assertion proves
            // nothing about whether the rules run at all.
            await FluentActions
                .Awaiting(() => update.ExecuteAsync(new UpdateHotkeyCommand(id, stillBad), default))
                .Should().ThrowAsync<FluentValidation.ValidationException>(
                    "the Owner cannot save the Item until the bad value is gone");

            Result<HotkeyDto> repaired = await update.ExecuteAsync(
                new UpdateHotkeyCommand(id, stillBad with { ContextValue = "a b" }), default);

            repaired.IsSuccess.Should().BeTrue(
                "the edit dialog is the repair route, so Update must accept the fixed values");
            repaired.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(work.Id);
        }

        // 5. The Profile script now contains it.
        await using (AppDbContext db = fx.CreateContext())
        {
            string after = await GenerateAsync(db, owner, work.Id);
            after.Should().Contain("recovhk");
        }
    }
}
