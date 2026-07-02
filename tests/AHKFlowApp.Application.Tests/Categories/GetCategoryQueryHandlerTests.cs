using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Categories;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

[Collection("CategoryDb")]
[Trait("Category", "Integration")]
public sealed class GetCategoryQueryHandlerTests(CategoryDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));

    private ICurrentUser CurrentUser()
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return user;
    }

    [Fact]
    public async Task Get_ReturnsNotFound_WhenIdDoesNotExist()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new GetCategoryQueryHandler(ctx, CurrentUser());

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new GetCategoryQuery(Guid.NewGuid()), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Get_ReturnsNotFound_WhenIdBelongsToAnotherUser()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var otherOwner = Guid.NewGuid();
        Category category = new CategoryBuilder().WithOwner(otherOwner).Named("Work").WithClock(_clock).Build();
        ctx.Categories.Add(category);
        await ctx.SaveChangesAsync();

        var sut = new GetCategoryQueryHandler(ctx, CurrentUser());

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new GetCategoryQuery(category.Id), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Get_ReturnsUnauthorized_WhenNoOid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new GetCategoryQueryHandler(ctx, user);

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new GetCategoryQuery(Guid.NewGuid()), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Get_ReturnsDto_WhenFound()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category category = new CategoryBuilder().WithOwner(_ownerOid).Named("Personal").WithClock(_clock).Build();
        ctx.Categories.Add(category);
        await ctx.SaveChangesAsync();

        var sut = new GetCategoryQueryHandler(ctx, CurrentUser());

        Result<CategoryDto> result = await sut.ExecuteAsync(
            new GetCategoryQuery(category.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Personal");
    }
}
