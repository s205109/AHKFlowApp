using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
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
            .WithOwner(owner).WithKey("n").WithCtrl().WithDescription("Old description")
            .WithClock(clock).AppliesToAll().Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        clock.Advance(TimeSpan.FromMinutes(5));

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), clock);
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("Updated description", "n", true, false, false, false, HotkeyAction.Run, "notepad.exe", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("Updated description");
        result.Value.UpdatedAt.Should().BeAfter(result.Value.CreatedAt);
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
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(attacker), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("Hijacked", "n", true, false, false, false, HotkeyAction.Run, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenMissingId_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(Guid.NewGuid(),
            new UpdateHotkeyDto("x", "n", true, false, false, false, HotkeyAction.Run, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(null), TimeProvider.System);
        var cmd = new UpdateHotkeyCommand(Guid.NewGuid(),
            new UpdateHotkeyDto("x", "n", true, false, false, false, HotkeyAction.Run, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

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
        var handler = new UpdateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System);
        // Try to change second to have same key+modifiers as first
        var cmd = new UpdateHotkeyCommand(second.Id,
            new UpdateHotkeyDto("Conflict", "f1", true, false, false, false, HotkeyAction.Run, "", null, true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
