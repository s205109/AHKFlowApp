using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dev;

[Collection("DevDb")]
[Trait("Category", "Integration")]
public sealed class SeedCategoriesCommandHandlerTests(DevDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
    private readonly AppEnvironment _devEnv = new(IsDevelopment: true);

    private ICurrentUser User()
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(_ownerOid);
        return u;
    }

    [Fact]
    public async Task Seed_Inserts_EightDefaultCategories_AndMarksUserPreference()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);

        Result<IReadOnlyList<CategoryDto>> result = await sut.ExecuteAsync(new SeedCategoriesCommand(Reset: false), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().HaveCount(8);
        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(8);

        UserPreference? pref = await ctx.UserPreferences.AsNoTracking().FirstOrDefaultAsync(p => p.OwnerOid == _ownerOid);
        pref.Should().NotBeNull();
        pref!.CategoriesSeededAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public async Task Seed_Idempotent_WhenCategoriesAlreadyExist()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Email").Build());
        await ctx.SaveChangesAsync();

        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);

        await sut.ExecuteAsync(new SeedCategoriesCommand(Reset: false), default);

        (await ctx.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(8);
    }

    [Fact]
    public async Task Reset_ClearsUserCategories_ThenInserts()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Custom1").Build());
        ctx.Categories.Add(new CategoryBuilder().WithOwner(_ownerOid).Named("Custom2").Build());
        var prefBefore = UserPreference.CreateDefault(_ownerOid, _clock);
        prefBefore.MarkCategoriesSeeded(_clock);
        ctx.UserPreferences.Add(prefBefore);
        await ctx.SaveChangesAsync();

        _clock.Advance(TimeSpan.FromMinutes(5));
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);
        await sut.ExecuteAsync(new SeedCategoriesCommand(Reset: true), default);

        List<string> names = await ctx.Categories.Where(c => c.OwnerOid == _ownerOid).Select(c => c.Name).ToListAsync();
        names.Should().HaveCount(8);
        names.Should().NotContain(["Custom1", "Custom2"]);

        UserPreference pref = await ctx.UserPreferences.AsNoTracking().FirstAsync(p => p.OwnerOid == _ownerOid);
        pref.CategoriesSeededAt.Should().Be(_clock.GetUtcNow());
    }

    [Fact]
    public async Task Reseed_AfterFullSeed_KeepsEightCategories()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, _devEnv);
        await sut.ExecuteAsync(new SeedCategoriesCommand(Reset: false), default);

        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new SeedCategoriesCommandHandler(ctx2, User(), _clock, _devEnv);
        await sut2.ExecuteAsync(new SeedCategoriesCommand(Reset: true), default);

        (await ctx2.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(8);
    }

    [Fact]
    public async Task Returns_NotFound_When_NotInDevelopment()
    {
        await using AppDbContext ctx = fx.CreateContext();
        AppEnvironment prodEnv = new(IsDevelopment: false);
        var sut = new SeedCategoriesCommandHandler(ctx, User(), _clock, prodEnv);

        Result<IReadOnlyList<CategoryDto>> result = await sut.ExecuteAsync(new SeedCategoriesCommand(Reset: false), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
