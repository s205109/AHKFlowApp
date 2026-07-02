using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
[Trait("Category", "Integration")]
public sealed class DeleteProfileCommandHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    [Fact]
    public async Task Deletes_owned_profile()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user, new EntityHistoryRecorder(ctx, TimeProvider.System));

        Result result = await sut.Handle(new DeleteProfileCommand(p.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        (await ctx.Profiles.AnyAsync(x => x.Id == p.Id)).Should().BeFalse();
    }

    [Fact]
    public async Task Returns_404_for_other_users_profile()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(Guid.NewGuid()).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user, new EntityHistoryRecorder(ctx, TimeProvider.System));

        Result result = await sut.Handle(new DeleteProfileCommand(p.Id), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_404_for_unknown_id()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user, new EntityHistoryRecorder(ctx, TimeProvider.System));

        Result result = await sut.Handle(new DeleteProfileCommand(Guid.NewGuid()), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new DeleteProfileCommandHandler(ctx, user, new EntityHistoryRecorder(ctx, TimeProvider.System));

        Result result = await sut.Handle(new DeleteProfileCommand(Guid.NewGuid()), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Delete_WritesHistoryForLinkedHotstringAndHotkey()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile profile = new ProfileBuilder().WithOwner(_ownerOid).Build();
        Hotstring hotstring = new HotstringBuilder()
            .WithOwner(_ownerOid)
            .WithTrigger("profile-history")
            .WithProfiles(profile.Id)
            .Build();
        Hotkey hotkey = new HotkeyBuilder()
            .WithOwner(_ownerOid)
            .WithKey("f19")
            .WithProfiles(profile.Id)
            .Build();
        ctx.Profiles.Add(profile);
        ctx.Hotstrings.Add(hotstring);
        ctx.Hotkeys.Add(hotkey);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user, new EntityHistoryRecorder(ctx, TimeProvider.System));

        Result result = await sut.Handle(new DeleteProfileCommand(profile.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        List<EntityHistory> histories = await ctx.EntityHistories
            .Where(h => h.OwnerOid == _ownerOid)
            .OrderBy(h => h.EntityType)
            .ToListAsync();
        histories.Should().HaveCount(2);
        histories.Should().OnlyContain(h => h.ChangeType == HistoryChangeType.Edit);

        EntityHistory hotstringHistory = histories.Single(h => h.EntityType == TrackedEntityType.Hotstring);
        HotstringSnapshot? hotstringSnapshot =
            JsonSerializer.Deserialize<HotstringSnapshot>(hotstringHistory.SnapshotJson);
        hotstringSnapshot!.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);

        EntityHistory hotkeyHistory = histories.Single(h => h.EntityType == TrackedEntityType.Hotkey);
        HotkeySnapshot? hotkeySnapshot =
            JsonSerializer.Deserialize<HotkeySnapshot>(hotkeyHistory.SnapshotJson);
        hotkeySnapshot!.ProfileIds.Should().ContainSingle().Which.Should().Be(profile.Id);
    }
}
