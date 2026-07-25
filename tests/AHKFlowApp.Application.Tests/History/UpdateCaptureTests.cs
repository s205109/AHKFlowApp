using System.Text.Json;
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
public sealed class UpdateCaptureTests(HistoryDbFixture fx)
{
    [Fact]
    public async Task UpdateHotstring_WritesBeforeImageOfPreviousState()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("cap1").WithReplacement("original").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        UpdateHotstringCommand cmd = new(entity.Id,
            new UpdateHotstringDto("cap1", "changed", null, true, true, true, null));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        EntityHistory entry = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotstring);
        entry.Version.Should().Be(1);
        entry.ChangeType.Should().Be(HistoryChangeType.Edit);
        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(entry.SnapshotJson);
        snapshot!.Replacement.Should().Be("original");
    }

    [Fact]
    public async Task UpdateHotstring_TwoUpdates_ProducesVersions1And2()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner).WithTrigger("cap2").WithReplacement("v0").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        foreach (string replacement in new[] { "v1", "v2" })
        {
            await using AppDbContext db = fx.CreateContext();
            UpdateHotstringCommandHandler handler = new(
                db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
            Result<HotstringDto> result = await handler.ExecuteAsync(
                new UpdateHotstringCommand(entity.Id,
                    new UpdateHotstringDto("cap2", replacement, null, true, true, true, null)), default);
            result.IsSuccess.Should().BeTrue();
        }

        await using AppDbContext verify = fx.CreateContext();
        List<int> versions = await verify.EntityHistories
            .Where(h => h.EntityId == entity.Id)
            .Select(h => h.Version).OrderBy(v => v).ToListAsync();
        versions.Should().Equal(1, 2);
    }

    [Fact]
    public async Task UpdateHotkey_WritesBeforeImageOfPreviousState()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).Build();
        string originalKey = entity.Key;

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        UpdateHotkeyCommand cmd = new(entity.Id,
            new UpdateHotkeyDto("changed desc", "F9", entity.ActionKind,
                Ctrl: false, Alt: false, Shift: false, Win: false,
                Text: entity.Text, SendKeysContent: entity.SendKeysContent,
                RunTarget: entity.RunTarget, RunTargetKind: entity.RunTargetKind,
                WindowOp: entity.WindowOp, RemapDest: entity.RemapDest, Body: entity.Body,
                ProfileIds: null, AppliesToAllProfiles: true, CategoryIds: null));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        EntityHistory entry = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotkey);
        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(entry.SnapshotJson);
        snapshot!.Key.Should().Be(originalKey);
    }
}
