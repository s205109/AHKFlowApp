using AHKFlowApp.Application.Commands.Hotkeys;
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

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
[Trait("Category", "Integration")]
public sealed class UpdateHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    // Most cases here exercise ownership, conflict and canonicalization, not the action payload.
    private static UpdateHotkeyDto Edit(
        string description,
        string key,
        Guid[]? profileIds = null,
        bool appliesToAllProfiles = true) =>
        new(description, key, HotkeyActionKind.Run,
            Ctrl: true, Alt: false, Shift: false, Win: false,
            Text: null, SendKeysContent: null,
            RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application,
            WindowOp: null, RemapDest: null, Body: null,
            ProfileIds: profileIds, AppliesToAllProfiles: appliesToAllProfiles);

    [Fact]
    public async Task Handle_WhenForeignProfileId_ReturnsInvalidWithIdentifier()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("n").WithCtrl().AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            Edit("x", "n", profileIds: [Guid.NewGuid()], appliesToAllProfiles: false));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Invalid);
        result.ValidationErrors.Single().Identifier.Should().Be("Input.ProfileIds");
    }

    [Fact]
    public async Task Handle_WhenValid_UpdatesAndReturnsUpdatedDto()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("n").WithCtrl().WithDescription("Old description")
            .WithClock(clock).AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), clock, new EntityHistoryRecorder(db, clock));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            Edit("Updated description", "n"));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("Updated description");
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
    }

    [Fact]
    public async Task Handle_WhenActionKindChanges_ClearsPreviousKindsColumns()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("n").WithCtrl()
            .WithRun("notepad.exe").AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        var cmd = new UpdateHotkeyCommand(entity.Id, new UpdateHotkeyDto(
            "Now types text", "n", HotkeyActionKind.SendText,
            Ctrl: true, Alt: false, Shift: false, Win: false,
            Text: "hello", SendKeysContent: null, RunTarget: null, RunTargetKind: null,
            WindowOp: null, RemapDest: null, Body: null,
            ProfileIds: null, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ActionKind.Should().Be(HotkeyActionKind.SendText);
        result.Value.Text.Should().Be("hello");
        result.Value.RunTarget.Should().BeNull();
        result.Value.RunTargetKind.Should().BeNull();

        await using AppDbContext verify = fx.CreateContext();
        Hotkey persisted = await verify.Hotkeys.SingleAsync(h => h.Id == entity.Id);
        persisted.ActionKind.Should().Be(HotkeyActionKind.SendText);
        persisted.Text.Should().Be("hello");
        persisted.RunTarget.Should().BeNull();
        persisted.RunTargetKind.Should().BeNull();
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey("n").WithCtrl().AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(attacker), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            Edit("Hijacked", "n"));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        var cmd = new UpdateHotkeyCommand(Guid.NewGuid(),
            Edit("x", "n"));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(null), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        var cmd = new UpdateHotkeyCommand(Guid.NewGuid(),
            Edit("x", "n"));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenDuplicateKeyModifiers_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().AppliesToAll().Build();
        Hotkey second = new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        // Try to change second to have same key+modifiers as first
        var cmd = new UpdateHotkeyCommand(second.Id,
            Edit("Conflict", "f1"));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Update_AliasOfExistingKey_IsRejectedAsDuplicate()
    {
        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder().WithOwner(owner).WithKey("Escape").WithCtrl().AppliesToAll().Build();
        Hotkey second = new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        // Try to change second to the alias "Esc", which canonicalizes to "Escape" and should
        // collide with the first hotkey's canonical key + matching modifiers.
        var cmd = new UpdateHotkeyCommand(second.Id,
            Edit("Alias conflict", "Esc"));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
