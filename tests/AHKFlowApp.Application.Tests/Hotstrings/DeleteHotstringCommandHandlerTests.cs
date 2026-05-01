using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class DeleteHotstringCommandHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_Deletes()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "del", "x", null, true, true, TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotstringCommandHandler(db, CurrentUserHelper.For(owner));

        Result result = await handler.Handle(new DeleteHotstringCommand(entity.Id), default);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.AnyAsync(h => h.Id == entity.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "del", "x", null, true, true, TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotstringCommandHandler(db, CurrentUserHelper.For(attacker));

        Result result = await handler.Handle(new DeleteHotstringCommand(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new DeleteHotstringCommandHandler(db, CurrentUserHelper.For(null));

        Result result = await handler.Handle(new DeleteHotstringCommand(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
