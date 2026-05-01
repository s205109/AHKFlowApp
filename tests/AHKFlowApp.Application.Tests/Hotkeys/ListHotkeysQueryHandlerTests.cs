using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
public sealed class ListHotkeysQueryHandlerTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_ScopedToOwner_IgnoresOtherTenants()
    {
        var owner = Guid.NewGuid();
        var other = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("mine").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(other).WithTrigger("theirs").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new ListHotkeysQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Should().OnlyContain(h => h.Trigger == "mine");
    }

    [Fact]
    public async Task Handle_FiltersByProfileId()
    {
        var owner = Guid.NewGuid();
        var profile = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).InProfile(profile).WithTrigger("a").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).InProfile(null).WithTrigger("b").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(ProfileId: profile), default);

        result.Value.Items.Should().HaveCount(1);
        result.Value.Items[0].Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_Paginates_WithCorrectTotalCount()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

        await using (AppDbContext seed = fx.CreateContext())
        {
            for (int i = 0; i < 5; i++)
            {
                seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger($"t{i}").WithClock(clock).Build());
                clock.Advance(TimeSpan.FromSeconds(1));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> page2 = await handler.Handle(
            new ListHotkeysQuery(Page: 2, PageSize: 2), default);

        page2.Value.TotalCount.Should().Be(5);
        page2.Value.Items.Should().HaveCount(2);
        page2.Value.Page.Should().Be(2);
        page2.Value.PageSize.Should().Be(2);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(null));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new ListHotkeysQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Search_MatchesTrigger()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("^!K").WithAction("notepad").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("F1").WithAction("help").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "^!K"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("^!K");
    }

    [Fact]
    public async Task Handle_Search_MatchesAction()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("a").WithAction("needle in a haystack").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("b").WithAction("nothing relevant").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "needle"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_Search_MatchesDescription()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("a").WithDescription("Open browser").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithTrigger("b").WithDescription("Lock workstation").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "browser"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_Search_CombinedWithProfileId()
    {
        var owner = Guid.NewGuid();
        var profile = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).InProfile(profile).WithTrigger("match").WithAction("x").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).InProfile(null).WithTrigger("match").WithAction("y").Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).InProfile(profile).WithTrigger("other").WithAction("z").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(ProfileId: profile, Search: "match"), default);

        result.Value.Items.Should().ContainSingle()
            .Which.Should().Match<HotkeyDto>(h => h.Trigger == "match" && h.ProfileId == profile);
    }
}
