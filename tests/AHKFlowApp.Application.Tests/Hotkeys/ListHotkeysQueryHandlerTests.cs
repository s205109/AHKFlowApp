using AHKFlowApp.Application;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
[Trait("Category", "Integration")]
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
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(new ListHotkeysQuery(), default);

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
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
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
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> page2 = await handler.ExecuteAsync(
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
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(null), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(new ListHotkeysQuery(), default);

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
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
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
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(Search: "browser"), default);

        result.Value.Items.Should().ContainSingle().Which.Description.Should().Be("Open browser");
    }

    [Fact]
    public async Task Handle_Search_MatchesRunTarget()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").WithRun("notepad.exe").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").WithRun("calc.exe").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(Search: "notepad"), default);

        result.Value.Items.Should().ContainSingle().Which.Key.Should().Be("f1");
    }

    // Search spans every typed payload column, so a row whose action carries its text in Text,
    // SendKeysContent or Body must be reachable by the same query the Run rows are.
    [Theory]
    [InlineData("greeting")]
    [InlineData("Volume_Up")]
    [InlineData("MsgBox")]
    public async Task Handle_Search_MatchesTypedPayloadColumns(string term)
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").WithSendText("a greeting").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").WithSendKeys("{Volume_Up}").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f3").WithCtrl().WithDescription("c").WithRawBody("MsgBox 1").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f4").WithCtrl().WithDescription("d").WithDisable().AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(Search: term), default);

        result.Value.Items.Should().ContainSingle();
    }

    // RemapDest is a payload column like the rest: the legacy single Parameters column made a
    // Remap destination findable by search, so dropping it from the predicate would be a
    // silent capability loss.
    [Fact]
    public async Task Handle_Search_MatchesRemapDest()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").WithRemap("Volume_Mute").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").WithDisable().AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(Search: "Volume_Mute"), default);

        result.Value.Items.Should().ContainSingle().Which.Key.Should().Be("f1");
    }

    [Fact]
    public async Task Handle_ActionKindFilter_ReturnsOnlyThatKind()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").WithRun("notepad.exe").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").WithSendText("hi").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(ActionKind: HotkeyActionKind.SendText), default);

        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Should().ContainSingle().Which.Key.Should().Be("f2");
    }

    [Fact]
    public async Task Handle_SortByActionKindAscending_OrdersByKind()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").WithDisable().AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").WithSendText("hi").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f3").WithCtrl().WithDescription("c").WithRun("notepad.exe").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(SortField: "actionKind", SortDescending: false), default);

        result.Value.Items.Select(h => h.ActionKind).Should().Equal(
            HotkeyActionKind.SendText, HotkeyActionKind.Run, HotkeyActionKind.Disable);
    }

    [Fact]
    public async Task Handle_DescriptionFilter_ComposesWithSearch()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("Open browser").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("Open notepad").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f3").WithCtrl().WithDescription("Lock workstation").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(DescriptionFilter: "Open"), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(2);
        result.Value.Items.Should().OnlyContain(h => h.Description.StartsWith("Open"));
    }

    [Fact]
    public async Task Handle_BooleanFilters_ReturnMatchingRows()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithDescription("b").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(Ctrl: true), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items.Single().Key.Should().Be("f1");
    }

    [Fact]
    public async Task Handle_SortByKeyAscending_ReturnsStableOrder()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f3").WithCtrl().WithDescription("c").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f1").WithCtrl().WithDescription("a").AppliesToAll().Build());
            seed.Hotkeys.Add(new HotkeyBuilder().WithOwner(owner).WithKey("f2").WithCtrl().WithDescription("b").AppliesToAll().Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new ListHotkeysQueryHandler(db, CurrentUserHelper.For(owner), new AppEnvironment(false), TimeProvider.System);

        Result<PagedList<HotkeyDto>> result = await handler.ExecuteAsync(
            new ListHotkeysQuery(SortField: "key", SortDescending: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Select(h => h.Key).Should().Equal("f1", "f2", "f3");
    }
}
