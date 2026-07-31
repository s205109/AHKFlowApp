using System.Text.Json;
using AHKFlowApp.Application.Commands.Hotkeys;
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

/// <summary>
/// Window context has to survive the whole history round trip: capture, restore, and revert.
/// Restore and revert have no duplicate pre-check, so the unique index is their only guard —
/// these tests prove a clash is reported and a different context is allowed.
/// </summary>
[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class HotkeyWindowContextHistoryTests(HistoryDbFixture fx)
{
    private async Task DeleteHotkeyViaHandlerAsync(Guid owner, Guid id)
    {
        await using AppDbContext db = fx.CreateContext();
        DeleteHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.ExecuteAsync(new DeleteHotkeyCommand(id), default);
        result.IsSuccess.Should().BeTrue();
    }

    private async Task<Result<HotkeyDto>> RestoreAsync(Guid owner, Guid id)
    {
        await using AppDbContext db = fx.CreateContext();
        RestoreHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));
        return await handler.ExecuteAsync(new RestoreHotkeyCommand(id), default);
    }

    [Fact]
    public async Task DeleteHotkey_CapturesContextInTheSnapshot()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f13").WithCtrl()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotkeyViaHandlerAsync(owner, entity.Id);

        await using AppDbContext read = fx.CreateContext();
        EntityHistory tombstone = await read.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.ChangeType == HistoryChangeType.Delete);
        HotkeySnapshot snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(tombstone.SnapshotJson)!;

        snapshot.ContextMatchType.Should().Be(WindowMatchType.Executable);
        snapshot.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public async Task RestoreHotkey_BringsBackTheContext()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f13").WithCtrl()
            .WithContext(WindowMatchType.TitleContains, "Untitled")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotkeyViaHandlerAsync(owner, entity.Id);

        Result<HotkeyDto> result = await RestoreAsync(owner, entity.Id);

        result.IsSuccess.Should().BeTrue();
        result.Value.ContextMatchType.Should().Be(WindowMatchType.TitleContains);
        result.Value.ContextValue.Should().Be("Untitled");
    }

    [Fact]
    public async Task RestoreHotkey_WhenLiveRowSharesCombinationAndContext_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f13").WithCtrl()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotkeyViaHandlerAsync(owner, entity.Id);

        // A different hotkey now occupies the same combination in the same window.
        Hotkey blocker = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f13").WithCtrl()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(blocker);
            await seed.SaveChangesAsync();
        }

        Result<HotkeyDto> result = await RestoreAsync(owner, entity.Id);

        result.Status.Should().Be(ResultStatus.Conflict);
        result.Errors.Should().ContainSingle().Which.Should().Be(
            "A hotkey with this key + modifier combination already exists for \"notepad.exe\".");
    }

    [Fact]
    public async Task RestoreHotkey_WhenLiveRowDiffersOnlyByContext_Succeeds()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f13").WithCtrl()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await DeleteHotkeyViaHandlerAsync(owner, entity.Id);

        Hotkey otherWindow = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f13").WithCtrl()
            .WithContext(WindowMatchType.Executable, "code.exe")
            .Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(otherWindow);
            await seed.SaveChangesAsync();
        }

        Result<HotkeyDto> result = await RestoreAsync(owner, entity.Id);

        result.IsSuccess.Should().BeTrue();
        result.Value.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public async Task RevertHotkey_BringsBackTheContext()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("original").WithKey("f12").WithCtrl()
            .WithSendText("payload")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateAsync(owner, entity.Id, contextValue: null, matchType: null);

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RevertHotkeyCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ContextMatchType.Should().Be(WindowMatchType.Executable);
        result.Value.ContextValue.Should().Be("notepad.exe");
    }

    [Fact]
    public async Task RevertHotkey_WhenAnotherRowTookTheSameContext_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("original").WithKey("f12").WithCtrl()
            .WithSendText("payload")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        // Version 1 captures the notepad.exe context; the edit frees that context up.
        await UpdateAsync(owner, entity.Id, contextValue: null, matchType: null);

        Hotkey blocker = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f12").WithCtrl()
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(blocker);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RevertHotkeyCommand(entity.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Conflict);
        result.Errors.Should().ContainSingle().Which.Should().Be(
            "A hotkey with this key + modifier combination already exists for \"notepad.exe\".");
    }

    [Fact]
    public async Task RevertHotkey_WhenBlockerUsesADifferentContext_Succeeds()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("original").WithKey("f12").WithCtrl()
            .WithSendText("payload")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateAsync(owner, entity.Id, contextValue: null, matchType: null);

        Hotkey otherWindow = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f12").WithCtrl()
            .WithContext(WindowMatchType.Executable, "code.exe")
            .Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(otherWindow);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.ExecuteAsync(new RevertHotkeyCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ContextValue.Should().Be("notepad.exe");
    }

    private async Task UpdateAsync(Guid owner, Guid id, WindowMatchType? matchType, string? contextValue)
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System,
            new EntityHistoryRecorder(db, TimeProvider.System));
        Result<HotkeyDto> result = await handler.ExecuteAsync(
            new UpdateHotkeyCommand(id, new UpdateHotkeyDto(
                "changed", "f12", HotkeyActionKind.SendText,
                Ctrl: true, Alt: false, Shift: false, Win: false,
                Text: "payload", SendKeysContent: null, RunTarget: null, RunTargetKind: null,
                WindowOp: null, RemapDest: null, Body: null,
                ProfileIds: null, AppliesToAllProfiles: true,
                CategoryIds: null,
                ContextMatchType: matchType, ContextValue: contextValue)),
            default);
        result.IsSuccess.Should().BeTrue(string.Join("; ", result.Errors));
    }
}
