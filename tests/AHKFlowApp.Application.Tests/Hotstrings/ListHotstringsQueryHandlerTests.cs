using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class ListHotstringsQueryHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_ScopedToOwner_IgnoresOtherTenants()
    {
        var owner = Guid.NewGuid();
        var other = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "mine", "x", null, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(other, "theirs", "y", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new ListHotstringsQuery(), default);

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
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "x", profile, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "y", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(ProfileId: profile), default);

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
                seed.Hotstrings.Add(Hotstring.Create(owner, $"t{i}", "x", null, true, true, clock));
                clock.Advance(TimeSpan.FromSeconds(1));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> page2 = await handler.Handle(
            new ListHotstringsQuery(Page: 2, PageSize: 2), default);

        page2.Value.TotalCount.Should().Be(5);
        page2.Value.Items.Should().HaveCount(2);
        page2.Value.Page.Should().Be(2);
        page2.Value.PageSize.Should().Be(2);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(null));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new ListHotstringsQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Search_MatchesTrigger()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "by the way", null, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "fyi", "for your info", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "btw"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task Handle_Search_MatchesReplacement()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "needle in a haystack", null, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "nothing relevant", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "needle"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_Search_IgnoresCaseByDefault()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "FOO bar", null, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "baz foo", null, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "foo"), default);

        result.Value.Items.Should().HaveCount(2);
    }

    [Fact]
    public async Task Handle_Search_CombinedWithProfileId()
    {
        var owner = Guid.NewGuid();
        var profile = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "match", "x", profile, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "match", "y", null, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "other", "z", profile, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotstringsQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(ProfileId: profile, Search: "match"), default);

        result.Value.Items.Should().ContainSingle()
            .Which.Should().Match<HotstringDto>(h => h.Trigger == "match" && h.ProfileId == profile);
    }
}
