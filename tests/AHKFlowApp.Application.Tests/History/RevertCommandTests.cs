using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.Commands.Hotstrings;
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

namespace AHKFlowApp.Application.Tests.History;

[Collection("HistoryDb")]
[Trait("Category", "Integration")]
public sealed class RevertCommandTests(HistoryDbFixture fx)
{
    private async Task UpdateHotstringViaHandlerAsync(Guid owner, Guid id, UpdateHotstringDto dto)
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        Result<HotstringDto> result = await handler.Handle(new UpdateHotstringCommand(id, dto), default);
        result.IsSuccess.Should().BeTrue();
    }

    private async Task UpdateHotkeyViaHandlerAsync(Guid owner, Guid id, UpdateHotkeyDto dto)
    {
        await using AppDbContext db = fx.CreateContext();
        UpdateHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));
        Result<HotkeyDto> result = await handler.Handle(new UpdateHotkeyCommand(id, dto), default);
        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task RevertHotstring_RestoresFieldsAndLinks_AndWritesNewBeforeImage()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("rv1")
            .WithReplacement("original")
            .WithProfiles(profile.Id)
            .WithCategory(category.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Categories.Add(category);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateHotstringViaHandlerAsync(owner, entity.Id,
            new UpdateHotstringDto("rv1", "changed", null, true, true, true, null));

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Replacement.Should().Be("original");
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);

        int versionCount = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versionCount.Should().Be(2);
    }

    [Fact]
    public async Task RevertHotstring_SnapshotProfileDeleted_DropsMissingLinkSilently()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger("rv2")
            .WithProfiles(profile.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateHotstringViaHandlerAsync(owner, entity.Id,
            new UpdateHotstringDto("rv2", "by the way", null, true, true, true, null));

        await using (AppDbContext del = fx.CreateContext())
        {
            del.Profiles.Remove(await del.Profiles.SingleAsync(p => p.Id == profile.Id));
            await del.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.AppliesToAllProfiles.Should().BeFalse();
        result.Value.ProfileIds.Should().BeEmpty();
    }

    [Fact]
    public async Task RevertHotstring_TriggerNowTakenByAnotherHotstring_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        Hotstring victim = new HotstringBuilder().WithOwner(owner).WithTrigger("rv3-old").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(victim);
            await seed.SaveChangesAsync();
        }

        await UpdateHotstringViaHandlerAsync(owner, victim.Id,
            new UpdateHotstringDto("rv3-new", "by the way", null, true, true, true, null));

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder().WithOwner(owner).WithTrigger("rv3-old").Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(victim.Id, 1), default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task RevertHotstring_UnknownVersion_ReturnsNotFound()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder().WithOwner(owner).WithTrigger("rv4").Build();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        RevertHotstringCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotstringDto> result = await handler.Handle(new RevertHotstringCommand(entity.Id, 9), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task RevertHotkey_RestoresFieldsAndLinks_AndWritesNewBeforeImage()
    {
        var owner = Guid.NewGuid();
        Profile profile = new ProfileBuilder().WithOwner(owner).Build();
        Category category = new CategoryBuilder().WithOwner(owner).Build();
        Hotkey entity = new HotkeyBuilder()
            .WithOwner(owner)
            .WithDescription("original")
            .WithKey("f12")
            .WithCtrl()
            .WithProfiles(profile.Id)
            .WithCategory(category.Id)
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.Add(profile);
            seed.Categories.Add(category);
            seed.Hotkeys.Add(entity);
            await seed.SaveChangesAsync();
        }

        await UpdateHotkeyViaHandlerAsync(owner, entity.Id,
            new UpdateHotkeyDto("changed", "f11", false, true, false, false, HotkeyAction.Send, "payload", null, true));

        await using AppDbContext db = fx.CreateContext();
        RevertHotkeyCommandHandler handler = new(
            db, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(db, TimeProvider.System));

        Result<HotkeyDto> result = await handler.Handle(new RevertHotkeyCommand(entity.Id, 1), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Description.Should().Be("original");
        result.Value.Key.Should().Be("f12");
        result.Value.Ctrl.Should().BeTrue();
        result.Value.Alt.Should().BeFalse();
        result.Value.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
        result.Value.CategoryIds.Should().ContainSingle().Which.Should().Be(category.Id);

        int versionCount = await db.EntityHistories.CountAsync(h => h.EntityId == entity.Id);
        versionCount.Should().Be(2);
    }
}
