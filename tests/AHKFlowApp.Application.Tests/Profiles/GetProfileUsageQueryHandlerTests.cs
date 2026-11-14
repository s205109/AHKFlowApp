using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
[Trait("Category", "Integration")]
public sealed class GetProfileUsageQueryHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    // Backlog 210: a profile delete gave no count of the items it leaves applying to no profile.
    [Fact]
    public async Task GetUsage_CountsOnlyItemsThatLinkToThisProfileAlone()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile work = new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").Build();
        Profile home = new ProfileBuilder().WithOwner(_ownerOid).WithName("Home").AsDefault(false).Build();
        Hotstring onlyWork = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("only-work").WithProfiles(work.Id).Build();
        Hotstring workAndHome = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("work-home").WithProfiles(work.Id, home.Id).Build();
        // WithProfiles first, because it turns the flag off. The flag is set on after it.
        Hotstring all = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("all").WithProfiles(work.Id).AppliesToAllProfiles().Build();
        Hotstring onlyHome = new HotstringBuilder().WithOwner(_ownerOid)
            .WithTrigger("only-home").WithProfiles(home.Id).Build();
        Hotstring theirs = new HotstringBuilder().WithOwner(Guid.NewGuid())
            .WithTrigger("theirs").WithProfiles(work.Id).Build();
        Hotkey onlyWorkKey = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithKey("f13").WithProfiles(work.Id).Build();
        Hotkey workAndHomeKey = new HotkeyBuilder().WithOwner(_ownerOid)
            .WithKey("f14").WithProfiles(work.Id, home.Id).Build();
        ctx.Profiles.AddRange(work, home);
        ctx.Hotstrings.AddRange(onlyWork, workAndHome, all, onlyHome, theirs);
        ctx.Hotkeys.AddRange(onlyWorkKey, workAndHomeKey);
        await ctx.SaveChangesAsync();

        // Guard the seed, so a builder change cannot turn the "all" row into a counted one.
        all.AppliesToAllProfiles.Should().BeTrue();
        all.Profiles.Should().ContainSingle(p => p.ProfileId == work.Id);

        var sut = new GetProfileUsageQueryHandler(ctx, UserFor(_ownerOid));

        Result<ProfileUsageDto> result = await sut.ExecuteAsync(
            new GetProfileUsageQuery(work.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().Be(new ProfileUsageDto(HotstringsLeftWithNoProfile: 1, HotkeysLeftWithNoProfile: 1));
    }

    // Backlog 210: the usage route must not reveal counts for another owner's profile.
    [Fact]
    public async Task GetUsage_ReturnsNotFound_WhenProfileBelongsToAnotherOwner()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile theirs = new ProfileBuilder().WithOwner(Guid.NewGuid()).Build();
        ctx.Profiles.Add(theirs);
        await ctx.SaveChangesAsync();

        var sut = new GetProfileUsageQueryHandler(ctx, UserFor(_ownerOid));

        Result<ProfileUsageDto> result = await sut.ExecuteAsync(
            new GetProfileUsageQuery(theirs.Id), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    private static ICurrentUser UserFor(Guid oid)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(oid);
        return user;
    }
}
