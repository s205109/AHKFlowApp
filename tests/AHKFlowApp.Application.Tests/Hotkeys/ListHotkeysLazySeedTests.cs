using AHKFlowApp.Application;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class ListHotkeysLazySeedTests(HotkeyDbFixture fx)
{
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-23T10:00:00Z"));
    private static readonly AppEnvironment s_dev = new(IsDevelopment: true);
    private static readonly AppEnvironment s_prod = new(IsDevelopment: false);

    [Fact]
    public async Task Handle_FirstCallInDev_Seeds12Hotkeys()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        Result<PagedList<HotkeyDto>> result = await sut.Handle(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_SetsHotkeysSeededAtMarker()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        UserPreference? pref = await ctx2.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref.Should().NotBeNull();
        pref!.HotkeysSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_SecondCallInDev_DoesNotDuplicateHotkeys()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        await sut.Handle(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListHotkeysQueryHandler(ctx2, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotkeyDto>> result = await sut2.Handle(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);
    }

    [Fact]
    public async Task Handle_FirstCallInProd_DoesNotSeed()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_prod, _clock);

        Result<PagedList<HotkeyDto>> result = await sut.Handle(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(0);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_AlsoSeedsCategories_WhenNoneExist()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        int categoryCount = await ctx2.Categories.CountAsync(c => c.OwnerOid == owner);
        categoryCount.Should().Be(8);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_LinksHotkeysToCategories()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.Handle(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        int linkedCount = await ctx2.HotkeyCategories
            .Where(hc => hc.Hotkey.OwnerOid == owner)
            .CountAsync();
        linkedCount.Should().BeGreaterThan(0);
    }
}
