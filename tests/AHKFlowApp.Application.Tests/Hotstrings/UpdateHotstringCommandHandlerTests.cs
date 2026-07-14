using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class UpdateHotstringCommandHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenValid_UpdatesAndReturnsUpdatedDto()
    {
        var owner = Guid.NewGuid();
        FixedClock clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var entity = Hotstring.Create(owner, new HotstringDefinition("btw", "old", null, true, true, true), clock);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler =
            new(db, CurrentUserHelper.For(owner), clock, new EntityHistoryRecorder(db, clock));
        UpdateHotstringCommand cmd = new(entity.Id,
            new UpdateHotstringDto("btw", "by the way", null, true, false, false, null));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Replacement.Should().Be("by the way");
        result.Value.IsEndingCharacterRequired.Should().BeFalse();
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
    }

    [Fact]
    public async Task Handle_RawWithLeadingComment_StripsDefinitionAndMergesDescription()
    {
        var owner = Guid.NewGuid();
        FixedClock clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        var entity = Hotstring.Create(owner, new HotstringDefinition("old", "old", null, true, true, true), clock);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler =
            new(db, CurrentUserHelper.For(owner), clock, new EntityHistoryRecorder(db, clock));
        UpdateHotstringCommand cmd = new(entity.Id, new UpdateHotstringDto(
            "ignored", "; moved note\n::btw::by the way", null, true, false, false, null,
            Kind: HotstringKind.Raw));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Trigger.Should().Be("btw");
        result.Value.Replacement.Should().Be("::btw::by the way");
        result.Value.Description.Should().Be("moved note");
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(owner, new HotstringDefinition("btw", "x", null, true, true, true), TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(attacker), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        UpdateHotstringCommand cmd = new(entity.Id,
            new UpdateHotstringDto("btw", "y", null, true, true, true, null));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        UpdateHotstringCommand cmd = new(Guid.NewGuid(),
            new UpdateHotstringDto("btw", "x", null, true, true, true, null));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTrigger_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        var first = Hotstring.Create(owner, new HotstringDefinition("first", "a", null, true, true, true), TimeProvider.System);
        var second = Hotstring.Create(owner, new HotstringDefinition("second", "b", null, true, true, true), TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        UpdateHotstringCommand cmd = new(second.Id,
            new UpdateHotstringDto("first", "b", null, true, true, true, null));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
