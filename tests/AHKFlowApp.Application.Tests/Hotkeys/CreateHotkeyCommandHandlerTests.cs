using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
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
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Open Notepad", "n", Ctrl: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Key.Should().Be("n");
        result.Value.Ctrl.Should().BeTrue();
        result.Value.Description.Should().Be("Open Notepad");
        result.Value.AppliesToAllProfiles.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotkeys.CountAsync(h => h.OwnerOid == owner)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(null), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto("Open Notepad", "n", AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenDuplicateKeyModifiers_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotkey existing = new HotkeyBuilder()
            .WithOwner(owner).WithKey("f1").WithCtrl().AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(existing);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Duplicate", "f1", Ctrl: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Handle_SameKeyDifferentOwners_Succeeds()
    {
        var owner1 = Guid.NewGuid();
        var owner2 = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner1).WithKey("f1").WithCtrl().AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner2), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Same key different owner", "f1", Ctrl: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Handle_SameKeyDifferentModifiers_Succeeds()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder()
                .WithOwner(owner).WithKey("f1").WithCtrl().AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        // Same key, different modifier (Alt instead of Ctrl)
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Alt version", "f1", Alt: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
    }
}
