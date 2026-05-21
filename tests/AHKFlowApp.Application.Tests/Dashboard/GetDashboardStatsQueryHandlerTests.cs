using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Dashboard;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dashboard;

[Collection("DashboardDb")]
public sealed class GetDashboardStatsQueryHandlerTests(DashboardDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly Guid _otherOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-13T12:00:00Z"));

    private GetDashboardStatsQueryHandler CreateSut(AppDbContext ctx)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return new GetDashboardStatsQueryHandler(ctx, user, _clock);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new GetDashboardStatsQueryHandler(ctx, user, _clock);

        Result<DashboardStatsDto> result = await sut.Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Counts_only_current_user_entities()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Hotstrings.AddRange(
            new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs1").WithClock(_clock).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs2").WithClock(_clock).Build(),
            new HotstringBuilder().WithOwner(_otherOid).WithTrigger("hs3").WithClock(_clock).Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithClock(_clock).Build());
        ctx.Profiles.AddRange(
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Default").AsDefault(true).WithClock(_clock).Build(),
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").AsDefault(false).WithClock(_clock).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Hotstrings.Total.Should().Be(2);
        result.Value.Hotkeys.Total.Should().Be(1);
        result.Value.Profiles.Total.Should().Be(2);
        result.Value.Profiles.Default.Should().Be(1);
        result.Value.Profiles.Active.Should().Be(1);
    }

    [Fact]
    public async Task Created_this_week_uses_seven_day_window()
    {
        await using AppDbContext ctx = fx.CreateContext();
        FakeTimeProvider inside1 = new(_clock.GetUtcNow().AddDays(-3));
        FakeTimeProvider inside2 = new(_clock.GetUtcNow().AddDays(-7).AddHours(1));
        FakeTimeProvider outside1 = new(_clock.GetUtcNow().AddDays(-7).AddHours(-1));
        FakeTimeProvider outside2 = new(_clock.GetUtcNow().AddDays(-30));
        ctx.Hotstrings.AddRange(
            new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("w1").WithClock(inside1).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("w2").WithClock(inside2).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("w3").WithClock(outside1).Build(),
            new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("w4").WithClock(outside2).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.Hotstrings.Total.Should().Be(4);
        result.Value.Hotstrings.CreatedThisWeek.Should().Be(2);
    }

    [Fact]
    public async Task Daily_buckets_length_is_fourteen_oldest_to_newest()
    {
        await using AppDbContext ctx = fx.CreateContext();
        string[] keys = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "o"];
        for (int i = 0; i < 14; i++)
        {
            FakeTimeProvider c = new(_clock.GetUtcNow().AddDays(-(13 - i)));
            ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithKey(keys[i]).WithClock(c).Build());
        }
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.Hotkeys.DailyBuckets.Should().HaveCount(14);
        result.Value.Hotkeys.DailyBuckets.Should().AllSatisfy(c => c.Should().Be(1));
    }

    [Fact]
    public async Task Recent_activity_returns_top_five_across_kinds_ordered_by_most_recent()
    {
        await using AppDbContext ctx = fx.CreateContext();
        FakeTimeProvider t1 = new(_clock.GetUtcNow().AddMinutes(-60));
        FakeTimeProvider t2 = new(_clock.GetUtcNow().AddMinutes(-50));
        FakeTimeProvider t3 = new(_clock.GetUtcNow().AddMinutes(-40));
        FakeTimeProvider t4 = new(_clock.GetUtcNow().AddMinutes(-30));
        FakeTimeProvider t5 = new(_clock.GetUtcNow().AddMinutes(-20));
        FakeTimeProvider t6 = new(_clock.GetUtcNow().AddMinutes(-10));

        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs1").WithClock(t1).Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithKey("a").WithDescription("hk2").WithClock(t2).Build());
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(_ownerOid).WithName("p3").AsDefault(false).WithClock(t3).Build());
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs4").WithClock(t4).Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithKey("b").WithDescription("hk5").WithClock(t5).Build());
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("hs6").WithClock(t6).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.RecentActivity.Should().HaveCount(5);
        result.Value.RecentActivity[0].Label.Should().Be("hs6");
        result.Value.RecentActivity[4].Label.Should().Be("hk2");
    }

    [Fact]
    public async Task Recent_activity_marks_updated_when_updated_after_created()
    {
        await using AppDbContext ctx = fx.CreateContext();
        FakeTimeProvider tCreate = new(_clock.GetUtcNow().AddMinutes(-30));
        Hotstring hs = new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("yw").WithClock(tCreate).Build();
        ctx.Hotstrings.Add(hs);
        await ctx.SaveChangesAsync();
        FakeTimeProvider tUpdate = new(_clock.GetUtcNow().AddMinutes(-5));
        hs.Update(hs.Trigger, hs.Replacement, hs.Description, hs.AppliesToAllProfiles, hs.IsEndingCharacterRequired, hs.IsTriggerInsideWord, tUpdate);
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.RecentActivity[0].Action.Should().Be("updated");
        result.Value.RecentActivity[0].Kind.Should().Be("hotstring");
    }

    [Fact]
    public async Task Recent_activity_excludes_other_user_entities()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_otherOid).WithTrigger("theirs").WithClock(_clock).Build());
        await ctx.SaveChangesAsync();

        Result<DashboardStatsDto> result = await CreateSut(ctx).Handle(new GetDashboardStatsQuery(), CancellationToken.None);

        result.Value.RecentActivity.Should().BeEmpty();
    }
}
