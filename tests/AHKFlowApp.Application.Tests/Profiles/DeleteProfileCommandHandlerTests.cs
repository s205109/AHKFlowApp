using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
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
        var sut = new DeleteProfileCommandHandler(ctx, user);

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
        var sut = new DeleteProfileCommandHandler(ctx, user);

        Result result = await sut.Handle(new DeleteProfileCommand(p.Id), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_404_for_unknown_id()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new DeleteProfileCommandHandler(ctx, user);

        Result result = await sut.Handle(new DeleteProfileCommand(Guid.NewGuid()), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new DeleteProfileCommandHandler(ctx, user);

        Result result = await sut.Handle(new DeleteProfileCommand(Guid.NewGuid()), CancellationToken.None);
        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
