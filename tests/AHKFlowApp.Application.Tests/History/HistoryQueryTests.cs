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
public sealed class HistoryQueryTests(HistoryDbFixture fx)
{
    private async Task<(Guid Owner, Hotstring Entity)> SeedHotstringWithOneEditAsync(string trigger)
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger(trigger).Build();

        await using AppDbContext seed = fx.CreateContext();
        seed.Hotstrings.Add(entity);
        EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
        await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, default);
        await seed.SaveChangesAsync();

        return (owner, entity);
    }

    private async Task<(Guid Owner, Hotkey Entity)> SeedHotkeyWithOneEditAsync(string key)
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey(key).Build();

        await using AppDbContext seed = fx.CreateContext();
        seed.Hotkeys.Add(entity);
        EntityHistoryRecorder recorder = new(seed, TimeProvider.System);
        await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Edit, default);
        await seed.SaveChangesAsync();

        return (owner, entity);
    }

    [Fact]
    public async Task GetHotstringHistory_ReturnsEntriesNewestFirst()
    {
        (Guid owner, Hotstring entity) = await SeedHotstringWithOneEditAsync("hq1");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HistoryEntryDto[]> result = await handler.ExecuteAsync(new GetHotstringHistoryQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        result.Value[0].Version.Should().Be(1);
        result.Value[0].ChangeType.Should().Be(HistoryChangeType.Edit);
    }

    [Fact]
    public async Task GetHotstringHistory_LiveItemWithNoHistory_ReturnsEmptyList()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("hq2").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HistoryEntryDto[]> result = await handler.ExecuteAsync(new GetHotstringHistoryQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().BeEmpty();
    }

    [Fact]
    public async Task GetHotstringHistory_OtherUsersItem_ReturnsNotFound()
    {
        (Guid _, Hotstring entity) = await SeedHotstringWithOneEditAsync("hq3");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryQueryHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result<HistoryEntryDto[]> result = await handler.ExecuteAsync(new GetHotstringHistoryQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task GetHotstringHistoryVersion_ReturnsDeserializedSnapshot()
    {
        (Guid owner, Hotstring entity) = await SeedHotstringWithOneEditAsync("hq4");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryVersionQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringHistoryVersionDto> result =
            await handler.ExecuteAsync(new GetHotstringHistoryVersionQuery(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Snapshot.Trigger.Should().Be("hq4");
    }

    [Fact]
    public async Task GetHotstringHistoryVersion_UnknownVersion_ReturnsNotFound()
    {
        (Guid owner, Hotstring entity) = await SeedHotstringWithOneEditAsync("hq5");

        await using AppDbContext db = fx.CreateContext();
        GetHotstringHistoryVersionQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringHistoryVersionDto> result =
            await handler.ExecuteAsync(new GetHotstringHistoryVersionQuery(entity.Id, 99), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task GetHotkeyHistory_ReturnsEntries()
    {
        (Guid owner, Hotkey entity) = await SeedHotkeyWithOneEditAsync("f10");

        await using AppDbContext db = fx.CreateContext();
        GetHotkeyHistoryQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HistoryEntryDto[]> result = await handler.ExecuteAsync(new GetHotkeyHistoryQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        result.Value[0].ChangeType.Should().Be(HistoryChangeType.Edit);
    }

    [Fact]
    public async Task GetHotkeyHistoryVersion_ReturnsDeserializedSnapshot()
    {
        (Guid owner, Hotkey entity) = await SeedHotkeyWithOneEditAsync("f11");

        await using AppDbContext db = fx.CreateContext();
        GetHotkeyHistoryVersionQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotkeyHistoryVersionDto> result =
            await handler.ExecuteAsync(new GetHotkeyHistoryVersionQuery(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Snapshot.Key.Should().Be("f11");
    }
}
