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
public sealed class DeleteCaptureTests(HistoryDbFixture fx)
{
    private async Task<(Guid Owner, Hotstring Entity, Guid ProfileId, Guid CategoryId)> SeedLinkedHotstringAsync(
        string trigger)
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger(trigger)
            .WithProfiles(profile.Id)
            .WithCategory(category.Id)
            .Build();

        await using AppDbContext seed = fx.CreateContext();
        seed.Profiles.Add(profile);
        seed.Categories.Add(category);
        seed.Hotstrings.Add(entity);
        await seed.SaveChangesAsync();

        return (owner, entity, profile.Id, category.Id);
    }

    [Fact]
    public async Task DeleteHotstring_WritesTombstoneIncludingLinks_AndRemovesRow()
    {
        (Guid owner, Hotstring entity, Guid profileId, Guid categoryId) = await SeedLinkedHotstringAsync("del1");

        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        Result result = await handler.Handle(new DeleteHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        (await db.Hotstrings.AnyAsync(h => h.Id == entity.Id)).Should().BeFalse();

        EntityHistory tombstone = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotstring);
        tombstone.ChangeType.Should().Be(HistoryChangeType.Delete);
        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(tombstone.SnapshotJson);
        snapshot!.ProfileIds.Should().ContainSingle().Which.Should().Be(profileId);
        snapshot.CategoryIds.Should().ContainSingle().Which.Should().Be(categoryId);
    }

    [Fact]
    public async Task BulkDeleteHotstrings_WritesOneTombstonePerDeletedRow()
    {
        var owner = Guid.NewGuid();
        Hotstring first = new HotstringBuilder().WithOwner(owner).WithTrigger("bulk1").Build();
        Hotstring second = new HotstringBuilder().WithOwner(owner).WithTrigger("bulk2").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        BulkDeleteHotstringsCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        Result<BulkDeleteResultDto> result = await handler.Handle(
            new BulkDeleteHotstringsCommand(new BulkDeleteRequestDto([first.Id, second.Id])), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.DeletedCount.Should().Be(2);
        List<EntityHistory> tombstones = await db.EntityHistories
            .Where(h => h.EntityId == first.Id || h.EntityId == second.Id)
            .ToListAsync();
        tombstones.Should().HaveCount(2);
        tombstones.Should().OnlyContain(t => t.ChangeType == HistoryChangeType.Delete);
    }

    [Fact]
    public async Task DeleteHotkey_WritesTombstone()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        Result result = await handler.Handle(new DeleteHotkeyCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        EntityHistory tombstone = await db.EntityHistories
            .SingleAsync(h => h.EntityId == entity.Id && h.EntityType == TrackedEntityType.Hotkey);
        tombstone.ChangeType.Should().Be(HistoryChangeType.Delete);
    }

    [Fact]
    public async Task BulkDeleteHotkeys_WritesOneTombstonePerDeletedRow()
    {
        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder().WithOwner(owner).WithKey("f6").Build();
        Hotkey second = new HotkeyBuilder().WithOwner(owner).WithKey("f7").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        BulkDeleteHotkeysCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        Result<BulkDeleteResultDto> result = await handler.Handle(
            new BulkDeleteHotkeysCommand(new BulkDeleteRequestDto([first.Id, second.Id])), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.DeletedCount.Should().Be(2);
        List<EntityHistory> tombstones = await db.EntityHistories
            .Where(h => h.EntityId == first.Id || h.EntityId == second.Id)
            .ToListAsync();
        tombstones.Should().HaveCount(2);
        tombstones.Should().OnlyContain(t => t.ChangeType == HistoryChangeType.Delete);
    }
}
