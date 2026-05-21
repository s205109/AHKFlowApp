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
public sealed class ListHotkeysFilterByCategoryTests(HotkeyDbFixture fx)
{
    [Fact]
    public async Task Handle_FiltersByCategoryIds_OrSemantics()
    {
        var owner = Guid.NewGuid();
        Category cat1 = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        Category cat2 = new CategoryBuilder().WithOwner(owner).Named("Home").Build();

        var hkA = Hotkey.Create(owner, "A", "a", true, false, false, false, HotkeyAction.Send, "", true, TimeProvider.System);
        var hkB = Hotkey.Create(owner, "B", "b", true, false, false, false, HotkeyAction.Send, "", true, TimeProvider.System);
        var hkC = Hotkey.Create(owner, "C", "c", true, false, false, false, HotkeyAction.Send, "", true, TimeProvider.System);
        var hkD = Hotkey.Create(owner, "D", "d", true, false, false, false, HotkeyAction.Send, "", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Categories.AddRange(cat1, cat2);
            seed.Hotkeys.AddRange(hkA, hkB, hkC, hkD);
            await seed.SaveChangesAsync();
            // A → cat1, B → cat2, C → cat1+cat2, D → none
            seed.HotkeyCategories.Add(HotkeyCategory.Create(hkA.Id, cat1.Id));
            seed.HotkeyCategories.Add(HotkeyCategory.Create(hkB.Id, cat2.Id));
            seed.HotkeyCategories.Add(HotkeyCategory.Create(hkC.Id, cat1.Id));
            seed.HotkeyCategories.Add(HotkeyCategory.Create(hkC.Id, cat2.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotkeysQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(CategoryIds: [cat1.Id, cat2.Id]), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(3);
        result.Value.Items.Select(h => h.Description).Should().BeEquivalentTo(["A", "B", "C"]);
    }

    [Fact]
    public async Task Handle_NoCategoryIdsFilter_ReturnsAll()
    {
        var owner = Guid.NewGuid();
        Category cat = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        var hkA = Hotkey.Create(owner, "Aa", "p", true, false, false, false, HotkeyAction.Send, "", true, TimeProvider.System);
        var hkB = Hotkey.Create(owner, "Bb", "q", false, true, false, false, HotkeyAction.Send, "", true, TimeProvider.System);

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Categories.Add(cat);
            seed.Hotkeys.AddRange(hkA, hkB);
            await seed.SaveChangesAsync();
            seed.HotkeyCategories.Add(HotkeyCategory.Create(hkA.Id, cat.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        ListHotkeysQueryHandler handler = new(db, CurrentUserHelper.For(owner));

        Result<PagedList<HotkeyDto>> result = await handler.Handle(
            new ListHotkeysQuery(CategoryIds: null), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Items.Should().HaveCount(2);
    }
}
