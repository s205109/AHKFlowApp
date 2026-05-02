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
            seed.Hotstrings.Add(Hotstring.Create(owner, "mine", "x", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(other, "theirs", "y", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new ListHotstringsQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Should().OnlyContain(h => h.Trigger == "mine");
    }

    [Fact]
    public async Task Handle_FiltersByProfileId_IncludesProfileScopedAndGlobal()
    {
        var owner = Guid.NewGuid();
        Guid profileId;

        await using (AppDbContext seed = fx.CreateContext())
        {
            var profile = Profile.Create(owner, "Work", true, "", "", TimeProvider.System);
            seed.Profiles.Add(profile);
            var scoped = Hotstring.Create(owner, "a", "x", false, true, true, TimeProvider.System);
            var global = Hotstring.Create(owner, "b", "y", true, true, true, TimeProvider.System);
            var other = Hotstring.Create(owner, "c", "z", false, true, true, TimeProvider.System);
            seed.Hotstrings.AddRange(scoped, global, other);
            await seed.SaveChangesAsync();
            profileId = profile.Id;
            seed.HotstringProfiles.Add(HotstringProfile.Create(scoped.Id, profileId));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(ProfileId: profileId), default);

        result.Value.Items.Should().HaveCount(2);
        result.Value.Items.Should().Contain(h => h.Trigger == "a");
        result.Value.Items.Should().Contain(h => h.Trigger == "b");
    }

    [Fact]
    public async Task Handle_Paginates_WithCorrectTotalCount()
    {
        var owner = Guid.NewGuid();
        FixedClock clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

        await using (AppDbContext seed = fx.CreateContext())
        {
            for (int i = 0; i < 5; i++)
            {
                seed.Hotstrings.Add(Hotstring.Create(owner, $"t{i}", "x", true, true, true, clock));
                clock.Advance(TimeSpan.FromSeconds(1));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

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
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(null));

        Result<PagedList<HotstringDto>> result = await handler.Handle(new ListHotstringsQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Search_MatchesTrigger()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, "btw", "by the way", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "fyi", "for your info", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

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
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "needle in a haystack", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "nothing relevant", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

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
            seed.Hotstrings.Add(Hotstring.Create(owner, "a", "FOO bar", true, true, true, TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, "b", "baz foo", true, true, true, TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(Search: "foo"), default);

        result.Value.Items.Should().HaveCount(2);
    }
}
