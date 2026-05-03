using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Entities;
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
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("mine").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(other).WithKey("f1").WithCtrl().WithDescription("theirs").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new ListHotkeysQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Should().OnlyContain(h => h.Description == "mine");
    }

    [Fact]
    public async Task Handle_FiltersByProfileId()
    {
        var owner = Guid.NewGuid();
        var clock = new FixedClock(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));
        Guid profileId;

        await using (AppDbContext seed = fx.CreateContext())
        {
            // Create a real profile so the FK constraint on HotkeyProfiles is satisfied
            var profileEntity = Profile.Create(owner, "Work", false, "", "", clock);
            seed.Profiles.Add(profileEntity);
            profileId = profileEntity.Id;

            // Hotkey A: applies to all profiles
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("global").AppliesToAll().Build());

            // Hotkey B: scoped to specific profile
            Hotkey hotkeyB = new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("profiled").AppliesToAll(false).Build();
            seed.Hotkeys.Add(hotkeyB);
            seed.HotkeyProfiles.Add(HotkeyProfile.Create(hotkeyB.Id, profileId));

            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(ProfileId: profileId), default);

        // Both "global" (appliesToAllProfiles=true) and "profiled" (has profile in junction) match
        result.Value.Items.Should().HaveCount(2);
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
                seed.Hotkeys.Add(new HotkeyBuilder()
                    .WithOwner(owner).WithKey($"f{i + 1}").WithCtrl()
                    .WithClock(clock).AppliesToAll().Build());
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
    public async Task Handle_Search_MatchesKey()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "f1"), default);

        result.Value.Items.Should().ContainSingle().Which.Key.Should().Be("f1");
    }

    [Fact]
    public async Task Handle_Search_MatchesDescription()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("Open browser").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("Lock workstation").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "browser"), default);

        result.Value.Items.Should().ContainSingle().Which.Description.Should().Be("Open browser");
    }

    [Fact]
    public async Task Handle_Search_MatchesParameters()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").WithParameters("notepad.exe").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").WithParameters("calc.exe").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(Search: "notepad"), default);

        result.Value.Items.Should().ContainSingle().Which.Key.Should().Be("f1");
    }
}
