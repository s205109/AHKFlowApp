using System.Text.Json;
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class ListDeletedQueryTests(HistoryDbFixture fx)
{
    private const int DeletedListCap = 500;

    private async Task<Hotstring> SeedAndDeleteHotstringAsync(Guid owner, string trigger)
    {
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger(trigger).Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.ExecuteAsync(new DeleteHotstringCommand(entity.Id), default);
        result.IsSuccess.Should().BeTrue();

        return entity;
    }

    private async Task<Hotkey> SeedAndDeleteHotkeyAsync(Guid owner, string key)
    {
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey(key).Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.ExecuteAsync(new DeleteHotkeyCommand(entity.Id), default);
        result.IsSuccess.Should().BeTrue();

        return entity;
    }

    private async Task SeedDeletedHotstringRowsAsync(Guid owner, int count)
    {
        await using AppDbContext db = fx.CreateContext();
        var clock = new FixedClock(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));

        for (int i = 0; i < count; i++)
        {
            HotstringSnapshot snapshot = new(
                $"deleted{i}",
                "replacement",
                null,
                true,
                true,
                true,
                [],
                [],
                clock.GetUtcNow(),
                clock.GetUtcNow());
            db.EntityHistories.Add(EntityHistory.Create(
                owner,
                TrackedEntityType.Hotstring,
                Guid.NewGuid(),
                1,
                HistoryChangeType.Delete,
                1,
                JsonSerializer.Serialize(snapshot),
                clock));
            clock.Advance(TimeSpan.FromSeconds(1));
        }

        await db.SaveChangesAsync();
    }

    private async Task SeedDeletedHotkeyRowsAsync(Guid owner, int count)
    {
        await using AppDbContext db = fx.CreateContext();
        var clock = new FixedClock(new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));

        for (int i = 0; i < count; i++)
        {
            HotkeySnapshot snapshot = new(
                $"Deleted key {i}",
                $"f{i}",
                true,
                false,
                false,
                false,
                true,
                [],
                [],
                clock.GetUtcNow(),
                clock.GetUtcNow(),
                HotkeyActionKind.Run,
                RunTarget: "notepad.exe",
                RunTargetKind: RunTargetKind.Application);
            db.EntityHistories.Add(EntityHistory.Create(
                owner,
                TrackedEntityType.Hotkey,
                Guid.NewGuid(),
                1,
                HistoryChangeType.Delete,
                1,
                JsonSerializer.Serialize(snapshot),
                clock));
            clock.Advance(TimeSpan.FromSeconds(1));
        }

        await db.SaveChangesAsync();
    }

    [Fact]
    public async Task ListDeletedHotstrings_ReturnsTombstonedItemWithSnapshotFields()
    {
        var owner = Guid.NewGuid();
        Hotstring deleted = await SeedAndDeleteHotstringAsync(owner, "ld1");

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotstringDto[]> result = await handler.ExecuteAsync(new ListDeletedHotstringsQuery(), default);

        result.IsSuccess.Should().BeTrue();
        DeletedHotstringDto dto = result.Value.Should().ContainSingle().Subject;
        dto.Id.Should().Be(deleted.Id);
        dto.Trigger.Should().Be("ld1");
        dto.Replacement.Should().Be(deleted.Replacement);
    }

    [Fact]
    public async Task ListDeletedHotstrings_LiveItemsWithEditHistory_AreExcluded()
    {
        var owner = Guid.NewGuid();
        Hotstring live = new HotstringBuilder().WithOwner(owner).WithTrigger("ld2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(live);
            EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
            await recorder.RecordHotstringAsync(live, HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotstringDto[]> result = await handler.ExecuteAsync(new ListDeletedHotstringsQuery(), default);

        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task ListDeletedHotstrings_OtherOwnersTombstones_AreExcluded()
    {
        var owner = Guid.NewGuid();
        await SeedAndDeleteHotstringAsync(owner, "ld3");

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result<DeletedHotstringDto[]> result = await handler.ExecuteAsync(new ListDeletedHotstringsQuery(), default);

        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task ListDeletedHotstrings_WhenMoreThanCap_ReturnsMostRecentCap()
    {
        var owner = Guid.NewGuid();
        await SeedDeletedHotstringRowsAsync(owner, DeletedListCap + 1);

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotstringDto[]> result = await handler.ExecuteAsync(new ListDeletedHotstringsQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(DeletedListCap);
        result.Value.Should().Contain(x => x.Trigger == $"deleted{DeletedListCap}");
        result.Value.Should().NotContain(x => x.Trigger == "deleted0");
    }

    [Fact]
    public async Task ListDeletedHotkeys_ReturnsTombstonedItemWithSnapshotFields()
    {
        var owner = Guid.NewGuid();
        Hotkey deleted = await SeedAndDeleteHotkeyAsync(owner, "f13");

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotkeysQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotkeyDto[]> result = await handler.ExecuteAsync(new ListDeletedHotkeysQuery(), default);

        result.IsSuccess.Should().BeTrue();
        DeletedHotkeyDto dto = result.Value.Should().ContainSingle().Subject;
        dto.Id.Should().Be(deleted.Id);
        dto.Key.Should().Be("f13");
        dto.Description.Should().Be(deleted.Description);
    }

    [Fact]
    public async Task ListDeletedHotkeys_WhenMoreThanCap_ReturnsMostRecentCap()
    {
        var owner = Guid.NewGuid();
        await SeedDeletedHotkeyRowsAsync(owner, DeletedListCap + 1);

        await using AppDbContext db = fx.CreateContext();
        ListDeletedHotkeysQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<DeletedHotkeyDto[]> result = await handler.ExecuteAsync(new ListDeletedHotkeysQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(DeletedListCap);
        result.Value.Should().Contain(x => x.Description == $"Deleted key {DeletedListCap}");
        result.Value.Should().NotContain(x => x.Description == "Deleted key 0");
    }
}
