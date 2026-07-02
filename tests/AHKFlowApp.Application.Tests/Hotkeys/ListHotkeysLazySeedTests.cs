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
[Trait("Category", "Integration")]
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

        Result<PagedList<HotkeyDto>> result = await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_SetsHotkeysSeededAtMarker()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

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
        await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListHotkeysQueryHandler(ctx2, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotkeyDto>> result = await sut2.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);
    }

    [Fact]
    public async Task Handle_FirstCallInProd_DoesNotSeed()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_prod, _clock);

        Result<PagedList<HotkeyDto>> result = await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(0);
    }

    [Fact]
    public async Task Handle_FirstCallInDev_AlsoSeedsCategories_WhenNoneExist()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        int categoryCount = await ctx2.Categories.CountAsync(c => c.OwnerOid == owner);
        categoryCount.Should().Be(8);
    }

    [Fact]
    public async Task Handle_AfterSeedHotkeysCommand_DoesNotReattemptSeed()
    {
        var owner = Guid.NewGuid();

        // Step 1: run the dev seed command (mirrors POST /api/v1/dev/hotkeys/seed)
        await using (AppDbContext seedCtx = fx.CreateContext())
        {
            var seedHandler = new AHKFlowApp.Application.Commands.Dev.SeedHotkeysCommandHandler(
                seedCtx, CurrentUserHelper.For(owner), TimeProvider.System, s_dev);
            await seedHandler.ExecuteAsync(new AHKFlowApp.Application.Commands.Dev.SeedHotkeysCommand(Reset: false), CancellationToken.None);
        }

        // Step 2: lazy list — must not re-attempt seed (marker should already be set)
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotkeyDto>> result = await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(12);

        // Marker persisted (the bug: lazy-seed would have detached pref on duplicate-key)
        await using AppDbContext verify = fx.CreateContext();
        UserPreference? pref = await verify.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref!.HotkeysSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_FirstCallInDev_LinksHotkeysToCategories()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);

        await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        int linkedCount = await ctx2.HotkeyCategories
            .Where(hc => hc.Hotkey.OwnerOid == owner)
            .CountAsync();
        linkedCount.Should().BeGreaterThan(0);
    }

    [Fact]
    public async Task Handle_WhenHotkeysExistWithNullMarker_SetsMarkerWithoutDuplicating()
    {
        // Simulate a post-migration dev DB: hotkeys already present but marker is null
        var owner = Guid.NewGuid();
        await using (AppDbContext seedCtx = fx.CreateContext())
        {
            // Insert a key combo that overlaps with the lazy-seed sample set (Ctrl+Alt+N)
            seedCtx.Hotkeys.Add(Hotkey.Create(owner, "Launch Notepad", "N",
                ctrl: true, alt: true, shift: false, win: false,
                AHKFlowApp.Domain.Enums.HotkeyAction.Run, "notepad.exe",
                appliesToAllProfiles: true, TimeProvider.System));
            await seedCtx.SaveChangesAsync();
        }

        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListHotkeysQueryHandler(ctx, CurrentUserHelper.For(owner), s_dev, _clock);
        Result<PagedList<HotkeyDto>> result = await sut.ExecuteAsync(new ListHotkeysQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();

        // Marker must be persisted so the next GET does not retry
        UserPreference? pref = await verify.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref!.HotkeysSeededAt.Should().NotBeNull();

        // No duplicate rows — Ctrl+Alt+N still exists exactly once
        int ctrlAltNCount = await verify.Hotkeys
            .CountAsync(h => h.OwnerOid == owner && h.Key == "N" && h.Ctrl && h.Alt && !h.Shift && !h.Win);
        ctrlAltNCount.Should().Be(1);
    }
}
