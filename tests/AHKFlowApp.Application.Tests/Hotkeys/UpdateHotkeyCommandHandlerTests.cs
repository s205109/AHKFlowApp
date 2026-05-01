using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class UpdateHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenValid_UpdatesAndReturnsUpdatedDto()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithTrigger("^!K").WithAction("old").WithClock(clock).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), clock);
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("^!K", "new", "updated", null));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Action.Should().Be("new");
        result.Value.Description.Should().Be("updated");
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithTrigger("^!K").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(attacker), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("^!K", "hijack", null, null));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(Guid.NewGuid(),
            new UpdateHotkeyDto("^!K", "x", null, null));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTrigger_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotkey first = new HotkeyBuilder().WithOwner(owner).WithTrigger("first").WithAction("a").Build();
        Hotkey second = new HotkeyBuilder().WithOwner(owner).WithTrigger("second").WithAction("b").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.AddRange(first, second);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(second.Id,
            new UpdateHotkeyDto("first", "b", null, null));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
