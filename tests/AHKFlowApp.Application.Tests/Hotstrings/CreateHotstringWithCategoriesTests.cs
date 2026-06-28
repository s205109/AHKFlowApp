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
[Trait("Category", "Integration")]
public sealed class CreateHotstringWithCategoriesTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenForeignCategoryId_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        var foreignCategoryId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "btw", "by the way",
            CategoryIds: [foreignCategoryId]));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.Status.Should().Be(ResultStatus.Invalid);
        result.ValidationErrors.Should().Contain(e => e.Identifier == "Input.CategoryIds");
    }

    [Fact]
    public async Task Handle_WhenValidCategoryIds_InsertsJunctionRowsAndReturnsIds()
    {
        var owner = Guid.NewGuid();
        Category cat1 = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        Category cat2 = new CategoryBuilder().WithOwner(owner).Named("Home").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Categories.AddRange(cat1, cat2);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "wfh", "working from home",
            CategoryIds: [cat1.Id, cat2.Id]));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEquivalentTo([cat1.Id, cat2.Id]);

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotstringCategories
            .CountAsync(hc => hc.HotstringId == result.Value.Id);
        junctionCount.Should().Be(2);
    }

    [Fact]
    public async Task Handle_WhenDuplicateCategoryIdsInInput_DedupesAndInsertsSingleJunctionRow()
    {
        var owner = Guid.NewGuid();
        Category cat = new CategoryBuilder().WithOwner(owner).Named("Work").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Categories.Add(cat);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "dup", "duplicate category test",
            CategoryIds: [cat.Id, cat.Id]));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().HaveCount(1);

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotstringCategories
            .CountAsync(hc => hc.HotstringId == result.Value.Id);
        junctionCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenNullCategoryIds_SucceedsWithEmptyCategoryIds()
    {
        var owner = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "nocats", "no categories",
            CategoryIds: null));

        Result<HotstringDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEmpty();
    }
}
