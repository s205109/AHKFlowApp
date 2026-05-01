using AHKFlowApp.Application;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class SeedHotstringsCommandHandlerTests(HotstringDbFixture fx)
{
    private static AppEnvironment DevEnv(bool isDev) => new(isDev);

    [Fact]
    public async Task Handle_InDevelopment_SeedsSamples()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new SeedHotstringsCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Count.Should().BeGreaterThanOrEqualTo(3);
    }

    [Fact]
    public async Task Handle_NotInDevelopment_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System, DevEnv(false));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new SeedHotstringsCommand(false), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_InDevEnv_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(null), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new SeedHotstringsCommand(false), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenSampleExists_SkipsIt()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "existing", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new SeedHotstringsCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().Contain(h => h.Trigger == "btw" && h.Replacement == "existing");
        result.Value.Items.Should().Contain(h => h.Trigger == "fyi");
        result.Value.Items.Should().Contain(h => h.Trigger == "brb");
    }

    [Fact]
    public async Task Handle_WithReset_RemovesExistingFirst()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "preexisting", "x", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new SeedHotstringsCommand(Reset: true), default);

        result.IsSuccess.Should().BeTrue();
        await using AppDbContext verify = fx.CreateContext();
        bool hasPreexisting = await verify.Hotstrings.AnyAsync(h => h.OwnerOid == owner && h.Trigger == "preexisting");
        hasPreexisting.Should().BeFalse();
    }
}
