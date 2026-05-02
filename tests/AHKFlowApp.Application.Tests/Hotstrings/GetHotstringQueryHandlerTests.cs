using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class GetHotstringQueryHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_ReturnsDto()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "g", "x", true, true, true, TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringDto> result = await handler.Handle(new GetHotstringQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "g", "x", true, true, true, TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(attacker));

        Result<HotstringDto> result = await handler.Handle(new GetHotstringQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(null));

        Result<HotstringDto> result = await handler.Handle(new GetHotstringQuery(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
