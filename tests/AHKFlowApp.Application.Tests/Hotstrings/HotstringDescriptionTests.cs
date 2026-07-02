using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Collection("HotstringDb")]
[Trait("Category", "Integration")]
public sealed class HotstringDescriptionTests(HotstringDbFixture fx)
{
    private static string NewTrigger() => $"d{Guid.NewGuid():N}"[..8];

    [Fact]
    public async Task Create_PersistsAndReturns_Description()
    {
        var owner = Guid.NewGuid();

        await using AppDbContext ctx = fx.CreateContext();
        CreateHotstringCommandHandler sut = new(ctx, CurrentUserHelper.For(owner), TimeProvider.System);

        Result<HotstringDto> r = await sut.ExecuteAsync(new CreateHotstringCommand(new CreateHotstringDto(
            Trigger: NewTrigger(),
            Replacement: "x",
            ProfileIds: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false,
            Description: "polite filler")), CancellationToken.None);

        r.IsSuccess.Should().BeTrue();
        r.Value.Description.Should().Be("polite filler");
    }

    [Fact]
    public async Task Create_TreatsWhitespaceAsNull()
    {
        var owner = Guid.NewGuid();

        await using AppDbContext ctx = fx.CreateContext();
        CreateHotstringCommandHandler sut = new(ctx, CurrentUserHelper.For(owner), TimeProvider.System);

        Result<HotstringDto> r = await sut.ExecuteAsync(new CreateHotstringCommand(new CreateHotstringDto(
            Trigger: NewTrigger(),
            Replacement: "x",
            ProfileIds: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: false,
            Description: "   ")), CancellationToken.None);

        r.IsSuccess.Should().BeTrue();
        r.Value.Description.Should().BeNull();
    }

    [Fact]
    public async Task Update_ChangesDescription()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger(NewTrigger())
            .WithDescription("original")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext ctx = fx.CreateContext();
        UpdateHotstringCommandHandler sut =
            new(ctx, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(ctx, TimeProvider.System));
        Result<HotstringDto> r = await sut.ExecuteAsync(new UpdateHotstringCommand(entity.Id, new UpdateHotstringDto(
            Trigger: entity.Trigger,
            Replacement: entity.Replacement,
            ProfileIds: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: entity.IsEndingCharacterRequired,
            IsTriggerInsideWord: entity.IsTriggerInsideWord,
            Description: "updated")), CancellationToken.None);

        r.IsSuccess.Should().BeTrue();
        r.Value.Description.Should().Be("updated");
    }

    [Fact]
    public async Task Update_TreatsWhitespaceAsNull()
    {
        var owner = Guid.NewGuid();
        Hotstring entity = new HotstringBuilder()
            .WithOwner(owner)
            .WithTrigger(NewTrigger())
            .WithDescription("original")
            .Build();

        await using (AppDbContext seed = fx.CreateContext())
        {
            seed.Hotstrings.Add(entity);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext ctx = fx.CreateContext();
        UpdateHotstringCommandHandler sut =
            new(ctx, CurrentUserHelper.For(owner), TimeProvider.System, new EntityHistoryRecorder(ctx, TimeProvider.System));
        Result<HotstringDto> r = await sut.ExecuteAsync(new UpdateHotstringCommand(entity.Id, new UpdateHotstringDto(
            Trigger: entity.Trigger,
            Replacement: entity.Replacement,
            ProfileIds: null,
            AppliesToAllProfiles: true,
            IsEndingCharacterRequired: entity.IsEndingCharacterRequired,
            IsTriggerInsideWord: entity.IsTriggerInsideWord,
            Description: "   ")), CancellationToken.None);

        r.IsSuccess.Should().BeTrue();
        r.Value.Description.Should().BeNull();
    }
}
