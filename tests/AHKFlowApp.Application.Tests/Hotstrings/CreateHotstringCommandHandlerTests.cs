using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class CreateHotstringCommandHandlerTests(HotstringDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    [Fact]
    public async Task Handle_WhenValid_CreatesAndReturnsDto()
    {
        await using AppDbContext db = fx.CreateContext();
        var owner = Guid.NewGuid();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", "by the way"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.Trigger.Should().Be("btw");

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner)).Should().Be(1);
    }

    [Fact]
    public async Task Handle_WhenProfilesAndCategories_ReturnsDtoWithBothIdSets()
    {
        var owner = Guid.NewGuid();
        Profile prof1 = new ProfileBuilder().WithOwner(owner).WithName("Work").Build();
        Profile prof2 = new ProfileBuilder().WithOwner(owner).WithName("Home").AsDefault(false).Build();
        Category cat1 = new CategoryBuilder().WithOwner(owner).Named("Email").Build();
        Category cat2 = new CategoryBuilder().WithOwner(owner).Named("Chat").Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Profiles.AddRange(prof1, prof2);
            seed.Categories.AddRange(cat1, cat2);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "both", "profiles and categories",
            ProfileIds: [prof1.Id, prof2.Id],
            AppliesToAllProfiles: false,
            CategoryIds: [cat1.Id, cat2.Id]));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.ProfileIds.Should().BeEquivalentTo([prof1.Id, prof2.Id]);
        result.Value.CategoryIds.Should().BeEquivalentTo([cat1.Id, cat2.Id]);
    }

    [Fact]
    public async Task Handle_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(null), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("btw", "by the way"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Handle_WhenDuplicateTriggerInSameProfile_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(
                owner, new HotstringDefinition("dup", "first", null, true, true, true), _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("dup", "second"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Handle_SameTriggerDifferentOwners_Succeeds()
    {
        var owner1 = Guid.NewGuid();
        var owner2 = Guid.NewGuid();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(Hotstring.Create(
                owner1, new HotstringDefinition("shared", "x", null, true, true, true), _clock));
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner2), _clock);

        Result<HotstringDto> result = await handler.ExecuteAsync(
            new CreateHotstringCommand(new CreateHotstringDto("shared", "y")), default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task ExecuteAsync_DuplicateTriggerSameContext_ReturnsConflict()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder()
                .WithOwner(owner).WithTrigger("ctx").WithReplacement("first")
                .WithContext(WindowMatchType.Executable, "notepad.exe")
                .Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "ctx", "second",
            ContextMatchType: WindowMatchType.Executable, ContextValue: "notepad.exe"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task ExecuteAsync_DuplicateTriggerDifferentContext_Succeeds()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder()
                .WithOwner(owner).WithTrigger("ctx2").WithReplacement("first")
                .WithContext(WindowMatchType.Executable, "notepad.exe")
                .Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "ctx2", "second",
            ContextMatchType: WindowMatchType.WindowClass, ContextValue: "Notepad"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();
    }

    [Fact]
    public async Task ExecuteAsync_DuplicateTriggerGlobalVsContexted_Succeeds()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            // Existing GLOBAL row (no context).
            seed.Hotstrings.Add(new HotstringBuilder()
                .WithOwner(owner).WithTrigger("ctx3").WithReplacement("global")
                .Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto(
            "ctx3", "contexted",
            ContextMatchType: WindowMatchType.Executable, ContextValue: "notepad.exe"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.IsSuccess.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == owner && h.Trigger == "ctx3")).Should().Be(2);
    }

    [Fact]
    public async Task ExecuteAsync_Conflict_MessageMentionsContext()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(new HotstringBuilder()
                .WithOwner(owner).WithTrigger("ctx4").WithReplacement("first")
                .Build());
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new CreateHotstringCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new CreateHotstringCommand(new CreateHotstringDto("ctx4", "second"));

        Result<HotstringDto> result = await handler.ExecuteAsync(cmd, default);

        result.Status.Should().Be(ResultStatus.Conflict);
        result.Errors.Should().Contain(e => e.Contains("context", StringComparison.OrdinalIgnoreCase));
    }
}
