using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

[Collection("HotkeyDb")]
[Trait("Category", "Integration")]
public sealed class CreateHotkeyWithCategoriesTests(HotkeyDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenForeignCategoryId_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        var foreignCategoryId = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Open Notepad", "n", Ctrl: true, AppliesToAllProfiles: true,
            CategoryIds: [foreignCategoryId]));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

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
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Open Notepad", "n", Ctrl: true, AppliesToAllProfiles: true,
            CategoryIds: [cat1.Id, cat2.Id]));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEquivalentTo([cat1.Id, cat2.Id]);

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotkeyCategories
            .CountAsync(hc => hc.HotkeyId == result.Value.Id);
        junctionCount.Should().Be(2);
    }

    [Fact]
    public async Task Handle_WhenNullCategoryIds_SucceedsWithEmptyCategoryIds()
    {
        var owner = Guid.NewGuid();

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotkeyCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotkeyCommand(new CreateHotkeyDto(
            "Open Notepad", "n", Ctrl: true, AppliesToAllProfiles: true,
            CategoryIds: null));

        Result<HotkeyDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEmpty();
    }
}
