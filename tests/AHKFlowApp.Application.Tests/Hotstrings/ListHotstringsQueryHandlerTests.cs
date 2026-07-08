using AHKFlowApp.Application;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class ListHotstringsQueryHandlerTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_ScopedToOwner_IgnoresOtherTenants()
    {
        var owner = Guid.NewGuid();
        var other = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("mine", "x", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(other, new HotstringDefinition("theirs", "y", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new ListHotstringsQuery(), default);

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
            var scoped = Hotstring.Create(owner, new HotstringDefinition("a", "x", null, false, true, true), TimeProvider.System);
            var global = Hotstring.Create(owner, new HotstringDefinition("b", "y", null, true, true, true), TimeProvider.System);
            var other = Hotstring.Create(owner, new HotstringDefinition("c", "z", null, false, true, true), TimeProvider.System);
            seed.Hotstrings.AddRange(scoped, global, other);
            await seed.SaveChangesAsync();
            profileId = profile.Id;
            seed.HotstringProfiles.Add(HotstringProfile.Create(scoped.Id, profileId));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
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
                seed.Hotstrings.Add(Hotstring.Create(
                    owner, new HotstringDefinition($"t{i}", "x", null, true, true, true), clock));
                clock.Advance(TimeSpan.FromSeconds(1));
            }
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> page2 = await handler.ExecuteAsync(
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
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(null), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new ListHotstringsQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Search_MatchesTrigger()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("btw", "by the way", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("fyi", "for your info", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(Search: "btw"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task Handle_Search_MatchesReplacement()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("a", "needle in a haystack", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("b", "nothing relevant", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(Search: "needle"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_Search_MatchesDescription()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("ka", "Klaus", "German greeting", true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("x", "y", "unrelated note", true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(Search: "german"), default);

        result.Value.Items.Should().ContainSingle().Which.Description.Should().Be("German greeting");
    }

    [Fact]
    public async Task Handle_Search_IgnoresCaseByDefault()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("a", "FOO bar", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("b", "baz foo", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(Search: "foo"), default);

        result.Value.Items.Should().HaveCount(2);
    }

    [Fact]
    public async Task Handle_TriggerFilter_ComposesWithSearch()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("btw", "by the way", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("btw2", "other text", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("fyi", "by the way", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(Search: "way", TriggerFilter: "btw"), default);

        result.Value.Items.Should().HaveCount(1);
        result.Value.Items[0].Trigger.Should().Be("btw");
    }

    [Fact]
    public async Task Handle_BooleanFilters_ReturnMatchingRows()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("a", "x", null, true, true, false), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("b", "x", null, true, false, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(IsEndingCharacterRequired: true, IsTriggerInsideWord: false), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_SortByTriggerAscending_ReturnsStableOrder()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("c", "x", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("a", "x", null, true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("b", "x", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(SortField: "trigger", SortDescending: false), default);

        result.Value.Items.Select(h => h.Trigger).Should().Equal("a", "b", "c");
    }

    [Fact]
    public async Task Handle_DescriptionFilter_MatchesDescription()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("a", "x", "German greeting", true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("b", "x", "unrelated note", true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("c", "x", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(DescriptionFilter: "greeting"), default);

        result.Value.Items.Should().ContainSingle().Which.Trigger.Should().Be("a");
    }

    [Fact]
    public async Task Handle_SortByDescriptionAscending_ReturnsStableOrder()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("a", "x", "charlie", true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("b", "x", "alpha", true, true, true), TimeProvider.System));
            seed.Hotstrings.Add(Hotstring.Create(owner, new HotstringDefinition("c", "x", "bravo", true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(
            new ListHotstringsQuery(SortField: "description", SortDescending: false), default);

        result.Value.Items.Select(h => h.Description).Should().Equal("alpha", "bravo", "charlie");
    }
}
