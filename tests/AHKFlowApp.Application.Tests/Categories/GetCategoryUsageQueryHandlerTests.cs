using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Categories;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Categories;

// Backlog 205: the category delete confirmation must say how many items use the category.
// These tests pin that the count matches the filter the delete handler uses.
[Collection("CategoryDb")]
[Trait("Category", "Integration")]
public sealed class GetCategoryUsageQueryHandlerTests(CategoryDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    private ICurrentUser CurrentUser()
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return user;
    }

    [Fact]
    public async Task GetUsage_CountsOnlyItemsLinkedToTheCategory()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category category = new CategoryBuilder().WithOwner(_ownerOid).Named("UsageCount").Build();
        ctx.Categories.Add(category);
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("usage-one").WithCategory(category.Id).Build());
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("usage-two").WithCategory(category.Id).Build());
        ctx.Hotstrings.Add(new HotstringBuilder().WithOwner(_ownerOid).WithTrigger("usage-none").Build());
        ctx.Hotkeys.Add(new HotkeyBuilder().WithOwner(_ownerOid).WithKey("f21").WithCategory(category.Id).Build());
        await ctx.SaveChangesAsync();

        var sut = new GetCategoryUsageQueryHandler(ctx, CurrentUser());

        Result<CategoryUsageDto> result = await sut.ExecuteAsync(
            new GetCategoryUsageQuery(category.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().Be(new CategoryUsageDto(HotstringCount: 2, HotkeyCount: 1));
    }

    [Fact]
    public async Task GetUsage_ReturnsNotFound_WhenCategoryBelongsToAnotherUser()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Category category = new CategoryBuilder().WithOwner(Guid.NewGuid()).Named("OtherUsage").Build();
        ctx.Categories.Add(category);
        await ctx.SaveChangesAsync();

        var sut = new GetCategoryUsageQueryHandler(ctx, CurrentUser());

        Result<CategoryUsageDto> result = await sut.ExecuteAsync(
            new GetCategoryUsageQuery(category.Id), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
