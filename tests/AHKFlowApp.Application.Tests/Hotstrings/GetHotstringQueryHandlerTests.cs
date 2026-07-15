using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class GetHotstringQueryHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_WhenOwned_ReturnsDto()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(
            owner, new HotstringDefinition("g", "x", null, true, true, true), TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringDto> result = await handler.ExecuteAsync(new GetHotstringQuery(entity.Id), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(entity.Id);
        result.Value.AppliesToAllProfiles.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task Handle_ClipboardDeliveryHotstring_ReturnsEffectiveDeliveryClipboardPaste()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(
            owner,
            new HotstringDefinition("g", "x", null, true, true, true, Delivery: HotstringDelivery.ClipboardPaste),
            TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<HotstringDto> result = await handler.ExecuteAsync(new GetHotstringQuery(entity.Id), default);

        result.Value.EffectiveDelivery.Should().Be(HotstringDelivery.ClipboardPaste);
    }

    [Fact]
    public async Task Handle_WhenCrossTenant_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        var attacker = Guid.NewGuid();
        var entity = Hotstring.Create(
            owner, new HotstringDefinition("g", "x", null, true, true, true), TimeProvider.System);
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(attacker));

        Result<HotstringDto> result = await handler.ExecuteAsync(new GetHotstringQuery(entity.Id), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        GetHotstringQueryHandler handler = new(db, CurrentUserHelper.For(null));

        Result<HotstringDto> result = await handler.ExecuteAsync(new GetHotstringQuery(Guid.NewGuid()), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
