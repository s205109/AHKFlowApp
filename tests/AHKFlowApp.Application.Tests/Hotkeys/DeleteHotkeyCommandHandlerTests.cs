using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
[Trait("Category", "Integration")]
public sealed class DeleteHotkeyCommandHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_Deletes()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), new EntityHistoryRecorder(db, TimeProvider.System));

        Result result = await handler.ExecuteAsync(new DeleteHotkeyCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotkeys.AnyAsync(h => h.Id == entity.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotkeyCommandHandler(
            db, CurrentUserHelper.For(attacker), new EntityHistoryRecorder(db, TimeProvider.System));

        Result result = await handler.ExecuteAsync(new DeleteHotkeyCommand(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotkeyCommandHandler(
            db, CurrentUserHelper.For(null), new EntityHistoryRecorder(db, TimeProvider.System));

        Result result = await handler.ExecuteAsync(new DeleteHotkeyCommand(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
