using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
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
public sealed class PurgeCommandTests(HistoryDbFixture fx)
{
    private async Task<Hotstring> SeedEditAndDeleteHotstringAsync(Guid owner, string trigger)
    {
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger(trigger).Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
            await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.Handle(new DeleteHotstringCommand(entity.Id), default);
        result.IsSuccess.Should().BeTrue();

        return entity;
    }

    private async Task<Hotkey> SeedEditAndDeleteHotkeyAsync(Guid owner, string key)
    {
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey(key).Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
            await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Edit, default);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        DeleteHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));
        Result result = await handler.Handle(new DeleteHotkeyCommand(entity.Id), default);
        result.IsSuccess.Should().BeTrue();

        return entity;
    }

    [Fact]
    public async Task PurgeHotstring_RemovesAllHistoryRows()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = await SeedEditAndDeleteHotstringAsync(owner, "pg1");

        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new PurgeDeletedHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        (await db.EntityHistories.AnyAsync(h => h.EntityId == entity.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task PurgeHotstring_LiveItem_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        Hotstring live = new HotstringBuilder().WithOwner(owner).WithTrigger("pg2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(live);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new PurgeDeletedHotstringCommand(live.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task PurgeHotstring_UnknownId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotstringCommandHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result result = await handler.Handle(new PurgeDeletedHotstringCommand(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task PurgeHotkey_RemovesAllHistoryRows()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = await SeedEditAndDeleteHotkeyAsync(owner, "f15");

        await using AppDbContext db = fx.CreateContext();
        PurgeDeletedHotkeyCommandHandler handler = new(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new PurgeDeletedHotkeyCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        (await db.EntityHistories.AnyAsync(h => h.EntityId == entity.Id)).Should().BeFalse();
    }
}
