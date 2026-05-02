using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class UpdateHotstringCommandHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenValid_UpdatesAndReturnsUpdatedDto()
    {
        var owner = Guid.NewGuid();
        FixedClock clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var entity = Hotstring.Create(owner, "btw", "old", true, true, true, clock);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner), clock);
        UpdateHotstringCommand cmd = new(entity.Id,
            new UpdateHotstringDto("btw", "by the way", null, true, false, false));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Replacement.Should().Be("by the way");
        result.Value.IsEndingCharacterRequired.Should().BeFalse();
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "btw", "x", true, true, true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(db, CurrentUserHelper.For(attacker), TimeProvider.System);
        UpdateHotstringCommand cmd = new(entity.Id,
            new UpdateHotstringDto("btw", "y", null, true, true, true));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System);
        UpdateHotstringCommand cmd = new(Guid.NewGuid(),
            new UpdateHotstringDto("btw", "x", null, true, true, true));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTrigger_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        var first = Hotstring.Create(owner, "first", "a", true, true, true, TimeProvider.System);
        var second = Hotstring.Create(owner, "second", "b", true, true, true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(db, CurrentUserHelper.For(owner), TimeProvider.System);
        UpdateHotstringCommand cmd = new(second.Id,
            new UpdateHotstringDto("first", "b", null, true, true, true));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
