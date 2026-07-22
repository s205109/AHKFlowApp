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
[Trait("Category", "Integration")]
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
            "Open Notepad", "n", HotkeyActionKind.Run, Ctrl: true,
            RunTarget: "notepad.exe", RunTargetKind: RunTargetKind.Application,
            AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Key.Should().Be("n");
        result.Value.Ctrl.Should().BeTrue();
        result.Value.Description.Should().Be("Open Notepad");
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ActionKind.Should().Be(HotkeyActionKind.Run);
        result.Value.RunTarget.Should().Be("notepad.exe");
        result.Value.RunTargetKind.Should().Be(RunTargetKind.Application);

        await using AppDbContext verify = fx.CreateContext();
        Hotkey persisted = await verify.Hotkeys.SingleAsync(h => h.OwnerOid == owner);
        persisted.ActionKind.Should().Be(HotkeyActionKind.Run);
        persisted.RunTarget.Should().Be("notepad.exe");
        persisted.RunTargetKind.Should().Be(RunTargetKind.Application);
        persisted.Text.Should().BeNull();
        persisted.SendKeysContent.Should().BeNull();
        persisted.WindowOp.Should().BeNull();
        persisted.RemapDest.Should().BeNull();
        persisted.Body.Should().BeNull();
    }

    [Fact]
    public async Task Handle_WhenForeignProfileId_ReturnsInvalidWithIdentifier()
    {
        await using AppDbContext db = fx.CreateContext();
        var owner = Guid.NewGuid();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Open Notepad", "n", HotkeyActionKind.Disable, Ctrl: true,
            ProfileIds: [Guid.NewGuid()], AppliesToAllProfiles: false));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Invalid);
        result.ValidationErrors.Single().Identifier.Should().Be("Input.ProfileIds");
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(null), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto("Open Notepad", "n", HotkeyActionKind.Disable, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

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
            "Duplicate", "f1", HotkeyActionKind.Disable, Ctrl: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

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
            "Same key different owner", "f1", HotkeyActionKind.Disable, Ctrl: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

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
            "Alt version", "f1", HotkeyActionKind.Disable, Alt: true, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task Create_AliasKey_PersistsCanonicalSpelling()
    {
        await using AppDbContext db = fx.CreateContext();
        var owner = Guid.NewGuid();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Close", "Esc", HotkeyActionKind.Disable, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Key.Should().Be("Escape");

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotkeys.SingleAsync(h => h.OwnerOid == owner)).Key.Should().Be("Escape");
    }

    [Fact]
    public async Task Create_AliasOfExistingKey_IsRejectedAsDuplicate()
    {
        var owner = Guid.NewGuid();
        Hotkey existing = new HotkeyBuilder()
            .WithOwner(owner).WithKey("Escape").AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(existing);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Close alias", "Esc", HotkeyActionKind.Disable, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Create_UnpaddedVkCode_IsRejectedAsDuplicateOfPaddedForm()
    {
        var owner = Guid.NewGuid();
        Hotkey existing = new HotkeyBuilder()
            .WithOwner(owner).WithKey("vk01").AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(existing);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Vk alias", "vk1", HotkeyActionKind.Disable, AppliesToAllProfiles: true));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }
}
