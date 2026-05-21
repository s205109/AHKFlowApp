using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class ListHotstringsFilterByCategoryTests(HotstringDbFixture fx)
{
    [Fact]
    public async Task Handle_FiltersByCategoryIds_OrSemantics()
    {
        var owner = Guid.NewGuid();
        Category cat1 = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        Category cat2 = new CategoryBuilder().WithOwner(owner).Named("Home").Build();

        var hsA = Hotstring.Create(owner, "aaa", "alpha", null, true, true, true, TimeProvider.System);
        var hsB = Hotstring.Create(owner, "bbb", "beta", null, true, true, true, TimeProvider.System);
        var hsC = Hotstring.Create(owner, "ccc", "gamma", null, true, true, true, TimeProvider.System);
        var hsD = Hotstring.Create(owner, "ddd", "delta", null, true, true, true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Categories.AddRange(cat1, cat2);
            seed.Hotstrings.AddRange(hsA, hsB, hsC, hsD);
            await seed.SaveChangesAsync();
            // A → cat1, B → cat2, C → cat1+cat2, D → none
            seed.HotstringCategories.Add(HotstringCategory.Create(hsA.Id, cat1.Id));
            seed.HotstringCategories.Add(HotstringCategory.Create(hsB.Id, cat2.Id));
            seed.HotstringCategories.Add(HotstringCategory.Create(hsC.Id, cat1.Id));
            seed.HotstringCategories.Add(HotstringCategory.Create(hsC.Id, cat2.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(CategoryIds: [cat1.Id, cat2.Id]), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(3);
        result.Value.Items.Select(h => h.Trigger).Should().BeEquivalentTo(["aaa", "bbb", "ccc"]);
    }

    [Fact]
    public async Task Handle_NoCategoryIdsFilter_ReturnsAll()
    {
        var owner = Guid.NewGuid();
        Category cat = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        var hsA = Hotstring.Create(owner, "xxx", "alpha", null, true, true, true, TimeProvider.System);
        var hsB = Hotstring.Create(owner, "yyy", "beta", null, true, true, true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Categories.Add(cat);
            seed.Hotstrings.AddRange(hsA, hsB);
            await seed.SaveChangesAsync();
            seed.HotstringCategories.Add(HotstringCategory.Create(hsA.Id, cat.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotstringsQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotstringDto>> result = await handler.Handle(
            new ListHotstringsQuery(CategoryIds: null), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(2);
    }
}
