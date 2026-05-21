using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
public sealed class UpdateHotstringWithCategoriesTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenForeignCategoryId_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "btw", "old", null, true, true, true, _clock);
        var foreignCategoryId = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new UpdateHotstringCommand(entity.Id,
            new UpdateHotstringDto("btw", "new", null, true, true, true, Description: null,
                CategoryIds: [foreignCategoryId]));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Invalid);
        result.ValidationErrors.Should().Contain(e => e.Identifier == "Input.CategoryIds");
    }

    [Fact]
    public async Task Handle_WhenValidCategoryIds_ReplacesJunctionRows()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "wfh", "work from home", null, true, true, true, _clock);
        Category cat1 = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        Category cat2 = new CategoryBuilder().WithOwner(owner).Named("Home").Build();
        Category cat3 = new CategoryBuilder().WithOwner(owner).Named("Other").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            seed.Categories.AddRange(cat1, cat2, cat3);
            await seed.SaveChangesAsync();
            // Seed initial junction to cat1 and cat2
            seed.HotstringCategories.Add(HotstringCategory.Create(entity.Id, cat1.Id));
            seed.HotstringCategories.Add(HotstringCategory.Create(entity.Id, cat2.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        // Update to only cat3
        var cmd = new UpdateHotstringCommand(entity.Id,
            new UpdateHotstringDto("wfh", "work from home", null, true, true, true, Description: null,
                CategoryIds: [cat3.Id]));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEquivalentTo([cat3.Id]);

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotstringCategories
            .CountAsync(hc => hc.HotstringId == entity.Id);
        junctionCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenEmptyCategoryIds_ClearsAllCategoryLinks()
    {
        var owner = Guid.NewGuid();
        var entity = Hotstring.Create(owner, "clr", "clear cats", null, true, true, true, _clock);
        Category cat = new CategoryBuilder().WithOwner(owner).Named("Work").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            seed.Categories.Add(cat);
            await seed.SaveChangesAsync();
            seed.HotstringCategories.Add(HotstringCategory.Create(entity.Id, cat.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new UpdateHotstringCommand(entity.Id,
            new UpdateHotstringDto("clr", "clear cats", null, true, true, true, Description: null,
                CategoryIds: []));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEmpty();

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotstringCategories
            .CountAsync(hc => hc.HotstringId == entity.Id);
        junctionCount.Should().Be(0);
    }
}
