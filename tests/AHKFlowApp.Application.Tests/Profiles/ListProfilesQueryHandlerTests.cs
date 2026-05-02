using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class ListProfilesQueryHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

    private ListProfilesQueryHandler CreateSut(AppDbContext ctx)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        return new ListProfilesQueryHandler(ctx, user, _clock);
    }

    [Fact]
    public async Task First_call_seeds_default_profile_when_user_has_none()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ListProfilesQueryHandler sut = CreateSut(ctx);

        Result<IReadOnlyList<ProfileDto>> result = await sut.Handle(new ListProfilesQuery(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        ProfileDto seeded = result.Value[0];
        seeded.Name.Should().Be("Default");
        seeded.IsDefault.Should().BeTrue();
        seeded.HeaderTemplate.Should().Be(DefaultProfileTemplates.Header);
        seeded.FooterTemplate.Should().Be(DefaultProfileTemplates.Footer);
        (await ctx.Profiles.CountAsync(p => p.OwnerOid == _ownerOid)).Should().Be(1);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new ListProfilesQueryHandler(ctx, user, _clock);

        Result<IReadOnlyList<ProfileDto>> result = await sut.Handle(new ListProfilesQuery(), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task Returns_users_profiles_ordered_default_first_then_name()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Profiles.AddRange(
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Zeta").AsDefault(false).Build(),
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Alpha").AsDefault(false).Build(),
            new ProfileBuilder().WithOwner(_ownerOid).WithName("Mid").AsDefault(true).Build(),
            new ProfileBuilder().WithOwner(Guid.NewGuid()).WithName("OtherUser").Build());
        await ctx.SaveChangesAsync();

        ListProfilesQueryHandler sut = CreateSut(ctx);
        Result<IReadOnlyList<ProfileDto>> result = await sut.Handle(new ListProfilesQuery(), CancellationToken.None);

        result.Value.Select(p => p.Name).Should().Equal("Mid", "Alpha", "Zeta");
    }
}
