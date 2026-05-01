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
public sealed class GetProfileQueryHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();

    [Fact]
    public async Task Returns_owned_profile()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).WithName("X").Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new GetProfileQueryHandler(ctx, user);

        Result<ProfileDto> result = await sut.Handle(new GetProfileQuery(p.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Id.Should().Be(p.Id);
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
        var sut = new GetProfileQueryHandler(ctx, user);

        Result<ProfileDto> result = await sut.Handle(new GetProfileQuery(p.Id), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }
}
