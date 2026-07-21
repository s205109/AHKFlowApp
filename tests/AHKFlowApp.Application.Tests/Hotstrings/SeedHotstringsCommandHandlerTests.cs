using AHKFlowApp.Application;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class SeedHotstringsCommandHandlerTests(HotstringDbFixture fx)
{
    // Derived from the shared seed set so adding a sample doesn't break every count assertion.
    private static readonly int SampleCount = HotstringSeedSamples.All.Length;

    private static AppEnvironment DevEnv(bool isDev) => new(isDev);

    private async Task SeedCategoriesAsync(Guid owner)
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedCategoriesCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
        await handler.ExecuteAsync(new SeedCategoriesCommand(Reset: false), default);
    }

    [Fact]
    public async Task Handle_InDevelopment_SeedsAllSamples()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(SampleCount);
    }

    [Fact]
    public async Task Handle_InDevelopment_SetsHotstringsSeededAtMarker()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext db = fx.CreateContext())
        {
            var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
            await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);
        }

        await using AppDbContext verify = fx.CreateContext();
        UserPreference? pref = await verify.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref.Should().NotBeNull();
        pref!.HotstringsSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_NotInDevelopment_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(Guid.NewGuid()), TimeProvider.System, DevEnv(false));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(false), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_InDevEnv_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(null), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(false), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenSampleExists_SkipsIt()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(
                owner, new HotstringDefinition("btw", "existing", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Should().Contain(h => h.Trigger == "btw" && h.Replacement == "existing");
        result.Value.Items.Should().Contain(h => h.Trigger == "fyi");
        result.Value.Items.Should().Contain(h => h.Trigger == "brb");
    }

    [Fact]
    public async Task Handle_WithReset_RemovesExistingFirst()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(
                owner, new HotstringDefinition("preexisting", "x", null, true, true, true), TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: true), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(SampleCount);
        await using AppDbContext verify = fx.CreateContext();
        bool hasPreexisting = await verify.Hotstrings.AnyAsync(h => h.OwnerOid == owner && h.Trigger == "preexisting");
        hasPreexisting.Should().BeFalse();
    }

    [Fact]
    public async Task Handle_WithReset_AfterFullSeed_KeepsAllSamples()
    {
        var owner = Guid.NewGuid();
        await SeedCategoriesAsync(owner);

        await using (AppDbContext first = fx.CreateContext())
        {
            var h1 = new SeedHotstringsCommandHandler(first, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
            await h1.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: true), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
    }

    [Fact]
    public async Task Handle_AfterCategoriesSeeded_AttachesCategoryLinks()
    {
        var owner = Guid.NewGuid();
        await SeedCategoriesAsync(owner);

        Dictionary<string, Guid> catByName;
        await using (AppDbContext lookup = fx.CreateContext())
        {
            catByName = await lookup.Categories
                .Where(c => c.OwnerOid == owner)
                .ToDictionaryAsync(c => c.Name, c => c.Id);
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
        result.Value.Items.Single(h => h.Trigger == "recieve").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["Autocorrect"]);
        result.Value.Items.Single(h => h.Trigger == "btw").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["Communication"]);
        result.Value.Items.Single(h => h.Trigger == ";arrow").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["Symbols"]);
        result.Value.Items.Single(h => h.Trigger == ";todo").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["Code"]);
    }

    [Fact]
    public async Task Handle_BeforeCategoriesSeeded_CreatesAllWithNoJunctions()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Should().OnlyContain(h => h.CategoryIds.Length == 0);

        await using AppDbContext verify = fx.CreateContext();
        int junctions = await verify.HotstringCategories.CountAsync(hc => hc.Hotstring.OwnerOid == owner);
        junctions.Should().Be(0);
    }

    [Fact]
    public async Task Handle_Backfill_AttachesMissingJunctions_OnRerun()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext before = fx.CreateContext())
        {
            var h1 = new SeedHotstringsCommandHandler(before, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
            await h1.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);
        }

        await SeedCategoriesAsync(owner);

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
    }

    [Fact]
    public async Task Handle_Rerun_WithCategories_DoesNotDuplicateJunctions()
    {
        var owner = Guid.NewGuid();
        await SeedCategoriesAsync(owner);

        await using (AppDbContext first = fx.CreateContext())
        {
            var h1 = new SeedHotstringsCommandHandler(first, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
            await h1.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);

        await using AppDbContext verify = fx.CreateContext();
        int junctions = await verify.HotstringCategories.CountAsync(hc => hc.Hotstring.OwnerOid == owner);
        junctions.Should().Be(SampleCount);
    }

    [Fact]
    public async Task Handle_WhenSampleExists_PreservesEffectiveDeliveryOfPreExistingClipboardRow()
    {
        var owner = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(
                owner,
                new HotstringDefinition(
                    "btw", "existing", null, true, true, true,
                    Delivery: HotstringDelivery.ClipboardPaste),
                TimeProvider.System));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));

        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().Contain(h => h.Trigger == "btw" && h.EffectiveDelivery == HotstringDelivery.ClipboardPaste);
    }

    [Fact]
    public async Task Handle_WithLowercaseCategories_MatchesSampleCategoryNamesCaseInsensitively()
    {
        var owner = Guid.NewGuid();
        await SeedCategoriesAsync(owner);

        await using (AppDbContext lowerCase = fx.CreateContext())
        {
            List<Category> categories = await lowerCase.Categories
                .Where(c => c.OwnerOid == owner)
                .ToListAsync();

            foreach (Category category in categories)
            {
                category.Update(category.Name.ToLowerInvariant(), TimeProvider.System);
            }

            await lowerCase.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotstringsCommandHandler(db, CurrentUserHelper.For(owner), TimeProvider.System, DevEnv(true));
        Result<PagedList<HotstringDto>> result = await handler.ExecuteAsync(new SeedHotstringsCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
    }
}
