using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
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
public sealed class UpdateHotkeyWithCategoriesTests(HotkeyDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenForeignCategoryId_ReturnsInvalid()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("Open Notepad").WithKey("n")
            .WithCtrl().WithAction(HotkeyAction.Send).WithParameters("").Build();
        var foreignCategoryId = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), _clock, new EntityHistoryRecorder(db, _clock));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("Open Notepad", "n", true, false, false, false,
                HotkeyAction.Send, "", null, true,
                CategoryIds: [foreignCategoryId]));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Invalid);
        result.ValidationErrors.Should().Contain(e => e.Identifier == "Input.CategoryIds");
    }

    [Fact]
    public async Task Handle_WhenReplacingProfiles_ReturnsDtoWithExactProfileIds()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("Profile swap").WithKey("p")
            .WithCtrl().WithAction(HotkeyAction.Send).WithParameters("").AppliesToAll(false).Build();
        Profile prof1 = new ProfileBuilder().WithOwner(owner).WithName("Old").Build();
        Profile prof2 = new ProfileBuilder().WithOwner(owner).WithName("New1").AsDefault(false).Build();
        Profile prof3 = new ProfileBuilder().WithOwner(owner).WithName("New2").AsDefault(false).Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            seed.Profiles.AddRange(prof1, prof2, prof3);
            await seed.SaveChangesAsync();
            seed.HotkeyProfiles.Add(HotkeyProfile.Create(entity.Id, prof1.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), _clock, new EntityHistoryRecorder(db, _clock));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("Profile swap", "p", true, false, false, false,
                HotkeyAction.Send, "", [prof2.Id, prof3.Id], false));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEquivalentTo([prof2.Id, prof3.Id]);

        await using AppDbContext verify = fx.CreateContext();
        List<Guid> dbProfileIds = await verify.HotkeyProfiles
            .Where(hp => hp.HotkeyId == entity.Id)
            .Select(hp => hp.ProfileId)
            .ToListAsync();
        dbProfileIds.Should().BeEquivalentTo([prof2.Id, prof3.Id]);
    }

    [Fact]
    public async Task Handle_WhenValidCategoryIds_ReplacesJunctionRows()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("Launch Terminal").WithKey("t")
            .WithCtrl().WithAction(HotkeyAction.Send).WithParameters("").Build();
        Category cat1 = new CategoryBuilder().WithOwner(owner).Named("Work").Build();
        Category cat2 = new CategoryBuilder().WithOwner(owner).Named("Home").Build();
        Category cat3 = new CategoryBuilder().WithOwner(owner).Named("Other").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            seed.Categories.AddRange(cat1, cat2, cat3);
            await seed.SaveChangesAsync();
            seed.HotkeyCategories.Add(HotkeyCategory.Create(entity.Id, cat1.Id));
            seed.HotkeyCategories.Add(HotkeyCategory.Create(entity.Id, cat2.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), _clock, new EntityHistoryRecorder(db, _clock));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("Launch Terminal", "t", true, false, false, false,
                HotkeyAction.Send, "", null, true,
                CategoryIds: [cat3.Id]));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEquivalentTo([cat3.Id]);

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotkeyCategories
            .CountAsync(hc => hc.HotkeyId == entity.Id);
        junctionCount.Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenEmptyCategoryIds_ClearsAllCategoryLinks()
    {
        var owner = Guid.NewGuid();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner).WithDescription("Close Window").WithKey("w")
            .WithCtrl().WithAction(HotkeyAction.Send).WithParameters("").Build();
        Category cat = new CategoryBuilder().WithOwner(owner).Named("Work").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotkeys.Add(entity);
            seed.Categories.Add(cat);
            await seed.SaveChangesAsync();
            seed.HotkeyCategories.Add(HotkeyCategory.Create(entity.Id, cat.Id));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateHotkeyCommandHandler(
            db, CurrentUserHelper.For(owner), _clock, new EntityHistoryRecorder(db, _clock));
        var cmd = new UpdateHotkeyCommand(entity.Id,
            new UpdateHotkeyDto("Close Window", "w", true, false, false, false,
                HotkeyAction.Send, "", null, true,
                CategoryIds: []));

        Result<HotkeyDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoryIds.Should().BeEmpty();

        await using AppDbContext verify = fx.CreateContext();
        int junctionCount = await verify.HotkeyCategories
            .CountAsync(hc => hc.HotkeyId == entity.Id);
        junctionCount.Should().Be(0);
    }
}
