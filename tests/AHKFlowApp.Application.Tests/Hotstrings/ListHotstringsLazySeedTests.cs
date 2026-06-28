using AHKFlowApp.Application;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class ListHotstringsLazySeedTests(HotstringDbFixture fx)
{
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-23T10:00:00Z"));
    private static readonly AppEnvironment s_dev = new(IsDevelopment: true);
    private static readonly AppEnvironment s_prod = new(IsDevelopment: false);

    [Fact]
    public async Task Handle_FirstCallInDev_Seeds12Hotstrings()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        Result<PagedList<HotstringDto>> result = await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_SetsHotstringsSeededAtMarker()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        UserPreference? pref = await ctx2.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref.Should().NotBeNull();
        pref!.HotstringsSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_SecondCallInDev_DoesNotDuplicateHotstrings()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListHotstringsQueryHandler(ctx2, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotstringDto>> result = await sut2.Handle(new ListHotstringsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);
    }

    [Fact]
    public async Task Handle_FirstCallInProd_DoesNotSeed()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_prod, _clock);

        Result<PagedList<HotstringDto>> result = await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(0);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_AlsoSeedsCategories_WhenNoneExist()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        int categoryCount = await ctx2.Categories.CountAsync(c => c.OwnerOid == owner);
        categoryCount.Should().Be(8);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_SetsCategoriesSeededMarker_WhenNoneExist()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        UserPreference? pref = await ctx2.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref!.CategoriesSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_FirstCallInDev_LinksHotstringsToCategories()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        int linkedCount = await ctx2.HotstringCategories
            .Where(hc => hc.Hotstring.OwnerOid == owner)
            .CountAsync();
        linkedCount.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Handle_AfterSeedHotstringsCommand_DoesNotReattemptSeed()
    {
        var owner = Guid.NewGuid();

        // Step 1: run the dev seed command (mirrors POST /api/v1/dev/hotstrings/seed)
        await using (AppDbContext seedCtx = fx.CreateContext())
        {
            var seedHandler = new AHKFlowApp.Application.Commands.Dev.SeedHotstringsCommandHandler(
                seedCtx, CurrentUserHelper.For(owner), TimeProvider.System, s_dev);
            await seedHandler.Handle(new AHKFlowApp.Application.Commands.Dev.SeedHotstringsCommand(Reset: false), CancellationToken.None);
        }

        // Step 2: lazy list — must not re-attempt seed (marker should already be set)
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotstringDto>> result = await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);

        // Marker persisted (the bug: lazy-seed would have detached pref on duplicate-key)
        await using AppDbContext verify = fx.CreateContext();
        UserPreference? pref = await verify.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref!.HotstringsSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_FirstCallInDev_UsesExistingCategories_WhenAlreadySeeded()
    {
        var owner = Guid.NewGuid();

        // Pre-seed categories via the categories handler pattern
        await using (AppDbContext seedCtx = fx.CreateContext())
        {
            seedCtx.Categories.Add(Category.Create(owner, "Communication", TimeProvider.System));
            await seedCtx.SaveChangesAsync();
            var pref = UserPreference.CreateDefault(owner, TimeProvider.System);
            pref.MarkCategoriesSeeded(TimeProvider.System);
            seedCtx.UserPreferences.Add(pref);
            await seedCtx.SaveChangesAsync();
        }

        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        // Should not have created duplicate categories
        await using AppDbContext ctx2 = fx.CreateContext();
        int communicationCount = await ctx2.Categories
            .CountAsync(c => c.OwnerOid == owner && c.Name == "Communication");
        communicationCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenHotstringsExistWithNullMarker_SetsMarkerWithoutDuplicating()
    {
        // Simulate a post-migration dev DB: hotstrings already present but marker is null
        var owner = Guid.NewGuid();
        await using (AppDbContext seedCtx = fx.CreateContext())
        {
            // Insert a trigger that overlaps with the lazy-seed sample set
            seedCtx.Hotstrings.Add(Hotstring.Create(owner, "btw", "pre-existing", null, true, true, true, TimeProvider.System));
            await seedCtx.SaveChangesAsync();
        }

        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotstringsQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotstringDto>> result = await sut.Handle(new ListHotstringsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();

        // Marker must be persisted so the next GET does not retry
        UserPreference? pref = await verify.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref!.HotstringsSeededAt.Should().NotBeNull();

        // No duplicate rows — "btw" still exists exactly once
        int btwCount = await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "btw");
        btwCount.Should().Be(1);
    }
}
