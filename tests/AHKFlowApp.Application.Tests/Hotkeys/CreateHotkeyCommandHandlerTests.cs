using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class CreateHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenValid_CreatesAndReturnsDto()
    {
        await using AppDbContext db = fx.CreateContext();
        var owner = Guid.NewGuid();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto("^!K", "Run notepad", "Open Notepad"));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Trigger.Should().Be("^!K");
        result.Value.Action.Should().Be("Run notepad");
        result.Value.Description.Should().Be("Open Notepad");

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotkeys.CountAsync(h => h.OwnerOid == owner)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(null), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto("^!K", "Run notepad"));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTriggerInSameProfile_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotkey existing = new HotkeyBuilder().WithOwner(owner).WithTrigger("dup").WithAction("first").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(existing);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto("dup", "second"));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Handle_SameTriggerDifferentOwners_Succeeds()
    {
        var owner1 = Guid.NewGuid();
        var owner2 = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner1).WithTrigger("shared").WithAction("x").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner2), _clock);

        Result<HotkeyDto> result = await handler.Handle(
            new CreateHotkeyCommand(new CreateHotkeyDto("shared", "y")), default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_SameTriggerDifferentProfiles_Succeeds()
    {
        var owner = Guid.NewGuid();
        var profileA = Guid.NewGuid();
        var profileB = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).InProfile(profileA).WithTrigger("^!K").WithAction("a").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);

        Result<HotkeyDto> result = await handler.Handle(
            new CreateHotkeyCommand(new CreateHotkeyDto("^!K", "b", null, profileB)), default);

        result.IsSuccess.Should().BeTrue();
    }
}
