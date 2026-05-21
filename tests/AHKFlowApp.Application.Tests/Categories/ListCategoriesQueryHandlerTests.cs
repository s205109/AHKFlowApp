using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Categories;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

[Collection("CategoryDb")]
public sealed class ListCategoriesQueryHandlerTests(CategoryDbFixture fx)
{
    private static readonly string[] s_expectedDefaults =
    [
        "App Launcher", "Autocorrect", "Code", "Communication",
        "DateTime", "Email", "Symbols", "Window Management",
    ];

    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));

    private ICurrentUser CurrentUser(Guid ownerOid)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(ownerOid);
        return user;
    }

    [Fact]
    public async Task Handle_FirstCall_LazySeeds_Defaults_AndSetsMarker()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, CurrentUser(owner), _clock);

        Result<PagedList<CategoryDto>> result = await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(8);
        result.Value.Items.Select(c => c.Name).Order().Should().Equal(s_expectedDefaults);

        UserPreference? pref = await ctx.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == owner);
        pref.Should().NotBeNull();
        pref!.CategoriesSeededAt.Should().NotBeNull();
    }

    [Fact]
    public async Task Handle_SecondCall_DoesNotReseed()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, CurrentUser(owner), _clock);

        await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListCategoriesQueryHandler(ctx2, CurrentUser(owner), _clock);
        Result<PagedList<CategoryDto>> result = await sut2.Handle(new ListCategoriesQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(8);
    }

    [Fact]
    public async Task Handle_DoesNotReseed_AfterUserDeletesAll_BecauseMarkerIsSet()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, CurrentUser(owner), _clock);

        // First call seeds defaults
        await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        // Delete all categories
        await using AppDbContext ctxDelete = fx.CreateContext();
        await ctxDelete.Categories.Where(c => c.OwnerOid == owner).ExecuteDeleteAsync();

        // Second call should NOT reseed (marker is set)
        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListCategoriesQueryHandler(ctx2, CurrentUser(owner), _clock);
        Result<PagedList<CategoryDto>> result = await sut2.Handle(new ListCategoriesQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(0);
    }

    [Fact]
    public async Task Handle_Search_FiltersByName_CaseInsensitive()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, CurrentUser(owner), _clock);

        // Seed defaults first
        await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListCategoriesQueryHandler(ctx2, CurrentUser(owner), _clock);
        Result<PagedList<CategoryDto>> result = await sut2.Handle(
            new ListCategoriesQuery(Search: "email"), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(1);
        result.Value.Items[0].Name.Should().Be("Email");
    }

    [Fact]
    public async Task Handle_Paging_ReturnsRequestedSlice_AndTotalCount()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, CurrentUser(owner), _clock);

        // Seed all 8 defaults
        await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        // Page 2 of page size 3 (sorted by name) — should return items 4-6
        await using AppDbContext ctx2 = fx.CreateContext();
        var sut2 = new ListCategoriesQueryHandler(ctx2, CurrentUser(owner), _clock);
        Result<PagedList<CategoryDto>> result = await sut2.Handle(
            new ListCategoriesQuery(Page: 2, PageSize: 3), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(8);
        result.Value.Items.Should().HaveCount(3);
        // Items 4-6 alphabetically: Communication, DateTime, Email
        result.Value.Items.Select(c => c.Name).Should().Equal("Communication", "DateTime", "Email");
    }

    [Fact]
    public async Task Handle_DoesNotShow_OtherUsers_Categories()
    {
        var owner = Guid.NewGuid();
        var otherOwner = Guid.NewGuid();

        // Seed defaults for other user
        await using AppDbContext ctxOther = fx.CreateContext();
        var sutOther = new ListCategoriesQueryHandler(ctxOther, CurrentUser(otherOwner), _clock);
        await sutOther.Handle(new ListCategoriesQuery(), CancellationToken.None);

        // Query for owner (no categories yet)
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new ListCategoriesQueryHandler(ctx, CurrentUser(owner), _clock);
        Result<PagedList<CategoryDto>> result = await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        // Owner gets their own seeded defaults, not other user's
        result.IsSuccess.Should().BeTrue();
        result.Value.TotalCount.Should().Be(8);
        result.Value.Items.Should().OnlyContain(c =>
            ctx.Categories.Any(cat => cat.Id == c.Id && cat.OwnerOid == owner));
    }

    [Fact]
    public async Task Handle_Returns_Unauthorized_WhenNoOid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new ListCategoriesQueryHandler(ctx, user, _clock);

        Result<PagedList<CategoryDto>> result = await sut.Handle(new ListCategoriesQuery(), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
