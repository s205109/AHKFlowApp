using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dev;

[Collection("DevDb")]
[Trait("Category", "Integration")]
public sealed class SeedHotkeysCommandHandlerTests(DevDbFixture fx)
{
    private const int SampleCount = 12;

    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly AppEnvironment _devEnv = new(IsDevelopment: true);

    private ICurrentUser User(Guid? oid = null)
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(oid ?? _ownerOid);
        return u;
    }

    private async Task SeedCategoriesAsync()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedCategoriesCommandHandler(db, User(), TimeProvider.System, _devEnv);
        await handler.Handle(new SeedCategoriesCommand(Reset: false), default);
    }

    private SeedHotkeysCommandHandler Sut(AppDbContext db, ICurrentUser? user = null) =>
        new(db, user ?? User(), TimeProvider.System, _devEnv);

    [Fact]
    public async Task Handle_InDevelopment_SeedsTwelveSamples()
    {
        await using AppDbContext db = fx.CreateContext();

        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(SampleCount);
    }

    [Fact]
    public async Task Handle_InDevelopment_SetsHotkeysSeededAtMarker()
    {
        await using (AppDbContext db = fx.CreateContext())
        {
            await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);
        }

        await using AppDbContext verify = fx.CreateContext();
        Domain.Entities.UserPreference? pref = await verify.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == _ownerOid);
        pref.Should().NotBeNull();
        pref!.HotkeysSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_NotInDevelopment_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new SeedHotkeysCommandHandler(db, User(), TimeProvider.System, new AppEnvironment(IsDevelopment: false));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new SeedHotkeysCommand(false), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Handle_WhenNoOid_InDevEnv_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        ICurrentUser noUser = Substitute.For<ICurrentUser>();
        noUser.Oid.Returns((Guid?)null);
        var handler = new SeedHotkeysCommandHandler(db, noUser, TimeProvider.System, _devEnv);

        Result<PagedList<HotkeyDto>> result = await handler.Handle(new SeedHotkeysCommand(false), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_Rerun_DoesNotDuplicateRows()
    {
        await using (AppDbContext first = fx.CreateContext())
            await Sut(first).Handle(new SeedHotkeysCommand(Reset: false), default);

        await using AppDbContext db = fx.CreateContext();
        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
    }

    [Fact]
    public async Task Handle_WithReset_AfterFullSeed_KeepsTwelveSamples()
    {
        await SeedCategoriesAsync();

        await using (AppDbContext first = fx.CreateContext())
            await Sut(first).Handle(new SeedHotkeysCommand(Reset: false), default);

        await using AppDbContext db = fx.CreateContext();
        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: true), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
    }

    [Fact]
    public async Task Handle_AfterCategoriesSeeded_AttachesCategoryLinks()
    {
        await SeedCategoriesAsync();

        Dictionary<string, Guid> catByName;
        await using (AppDbContext lookup = fx.CreateContext())
        {
            catByName = await lookup.Categories
                .Where(c => c.OwnerOid == _ownerOid)
                .ToDictionaryAsync(c => c.Name, c => c.Id);
        }

        await using AppDbContext db = fx.CreateContext();
        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
        result.Value.Items.Single(h => h.Description == "Launch Notepad").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["App Launcher"]);
        result.Value.Items.Single(h => h.Description == "Maximize window").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["Window Management"]);
        result.Value.Items.Single(h => h.Description == "Paste as plain text").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["Code"]);
        result.Value.Items.Single(h => h.Description == "Insert today's date").CategoryIds
            .Should().ContainSingle().Which.Should().Be(catByName["DateTime"]);
    }

    [Fact]
    public async Task Handle_BeforeCategoriesSeeded_CreatesTwelveWithNoJunctions()
    {
        await using AppDbContext db = fx.CreateContext();

        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Should().OnlyContain(h => h.CategoryIds.Length == 0);

        await using AppDbContext verify = fx.CreateContext();
        int junctions = await verify.HotkeyCategories.CountAsync(hc => hc.Hotkey.OwnerOid == _ownerOid);
        junctions.Should().Be(0);
    }

    [Fact]
    public async Task Handle_Backfill_AttachesMissingJunctions_OnRerun()
    {
        await using (AppDbContext before = fx.CreateContext())
            await Sut(before).Handle(new SeedHotkeysCommand(Reset: false), default);

        await SeedCategoriesAsync();

        await using AppDbContext db = fx.CreateContext();
        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
    }

    [Fact]
    public async Task Handle_Rerun_WithCategories_DoesNotDuplicateJunctions()
    {
        await SeedCategoriesAsync();

        await using (AppDbContext first = fx.CreateContext())
            await Sut(first).Handle(new SeedHotkeysCommand(Reset: false), default);

        await using AppDbContext db = fx.CreateContext();
        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);

        await using AppDbContext verify = fx.CreateContext();
        int junctions = await verify.HotkeyCategories.CountAsync(hc => hc.Hotkey.OwnerOid == _ownerOid);
        junctions.Should().Be(SampleCount);
    }

    [Fact]
    public async Task Handle_WithLowercaseCategories_MatchesSampleCategoryNamesCaseInsensitively()
    {
        await SeedCategoriesAsync();

        await using (AppDbContext lowerCase = fx.CreateContext())
        {
            List<Domain.Entities.Category> categories = await lowerCase.Categories
                .Where(c => c.OwnerOid == _ownerOid)
                .ToListAsync();

            foreach (Domain.Entities.Category category in categories)
            {
                category.Update(category.Name.ToLowerInvariant(), TimeProvider.System);
            }

            await lowerCase.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        Result<PagedList<HotkeyDto>> result = await Sut(db).Handle(new SeedHotkeysCommand(Reset: false), default);

        result.Value.Items.Should().HaveCount(SampleCount);
        result.Value.Items.Sum(h => h.CategoryIds.Length).Should().Be(SampleCount);
    }
}
