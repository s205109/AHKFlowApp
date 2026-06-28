using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Categories;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

[Collection("CategoryDb")]
[Trait("Category", "Integration")]
public sealed class DeleteCategoryCommandHandlerTests(CategoryDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    private ICurrentUser CurrentUser()
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return user;
    }

    [Fact]
    public async Task Delete_ReturnsNotFound_WhenIdDoesNotExist()
    {
        await using AppDbContext ctx = fx.CreateContext();
        var sut = new DeleteCategoryCommandHandler(ctx, CurrentUser());

        Result result = await sut.Handle(
            new DeleteCategoryCommand(Guid.NewGuid()), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Delete_ReturnsNotFound_WhenIdBelongsToAnotherUser()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category category = new CategoryBuilder().WithOwner(Guid.NewGuid()).Named("Other").Build();
        ctx.Categories.Add(category);
        await ctx.SaveChangesAsync();

        var sut = new DeleteCategoryCommandHandler(ctx, CurrentUser());

        Result result = await sut.Handle(
            new DeleteCategoryCommand(category.Id), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Delete_ReturnsUnauthorized_WhenNoOid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new DeleteCategoryCommandHandler(ctx, user);

        Result result = await sut.Handle(
            new DeleteCategoryCommand(Guid.NewGuid()), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Delete_RemovesCategory()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category category = new CategoryBuilder().WithOwner(_ownerOid).Named("ToDelete").Build();
        ctx.Categories.Add(category);
        await ctx.SaveChangesAsync();

        var sut = new DeleteCategoryCommandHandler(ctx, CurrentUser());

        Result result = await sut.Handle(
            new DeleteCategoryCommand(category.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        (await ctx.Categories.CountAsync(c => c.Id == category.Id))
            .Should().Be(0);
    }

    [Fact]
    public async Task Delete_CascadesJunctionRows_ButPreservesHotstring()
    {
        await using AppDbContext ctx = fx.CreateContext();

        Hotstring hotstring = new HotstringBuilder()
            .WithOwner(_ownerOid)
            .WithTrigger("casctest")
            .AppliesToAllProfiles()
            .Build();
        ctx.Hotstrings.Add(hotstring);

        Category category = new CategoryBuilder().WithOwner(_ownerOid).Named("CascadeTest").Build();
        ctx.Categories.Add(category);

        await ctx.SaveChangesAsync();

        ctx.HotstringCategories.Add(HotstringCategory.Create(hotstring.Id, category.Id));
        await ctx.SaveChangesAsync();

        var sut = new DeleteCategoryCommandHandler(ctx, CurrentUser());

        Result result = await sut.Handle(
            new DeleteCategoryCommand(category.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        (await ctx.Hotstrings.CountAsync(h => h.Id == hotstring.Id))
            .Should().Be(1);
        (await ctx.HotstringCategories.CountAsync(hc => hc.CategoryId == category.Id))
            .Should().Be(0);
    }
}
