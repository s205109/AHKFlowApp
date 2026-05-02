using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class GetHotkeyQueryHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_ReturnsDto()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey("g").WithCtrl().AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotkeyQueryHandler(db, CurrentUserHelper.For(owner));

        Result<HotkeyDto> result = await handler.Handle(new GetHotkeyQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder().WithOwner(owner).WithKey("g").WithCtrl().AppliesToAll().Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotkeyQueryHandler(db, CurrentUserHelper.For(attacker));

        Result<HotkeyDto> result = await handler.Handle(new GetHotkeyQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new GetHotkeyQueryHandler(db, CurrentUserHelper.For(null));

        Result<HotkeyDto> result = await handler.Handle(new GetHotkeyQuery(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
