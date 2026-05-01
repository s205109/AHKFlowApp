using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
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
public sealed class CreateProfileCommandHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

    [Fact]
    public async Task Creates_profile_for_authenticated_user()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);

        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("Work")), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Work");
        (await ctx.Profiles.CountAsync(p => p.OwnerOid == _ownerOid)).Should().Be(1);
    }

    [Fact]
    public async Task Returns_conflict_on_duplicate_name_for_same_owner()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").Build());
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("Work")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("Work")), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    [Fact]
    public async Task IsDefault_true_clears_existing_default_for_owner()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile existing = new ProfileBuilder().WithOwner(_ownerOid).WithName("Old").AsDefault(true).Build();
        ctx.Profiles.Add(existing);
        await ctx.SaveChangesAsync();

        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(_ownerOid);
        var sut = new CreateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.Handle(
            new CreateProfileCommand(new CreateProfileDto("New", IsDefault: true)), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        Profile reloaded = await ctx.Profiles.AsNoTracking().FirstAsync(p => p.Id == existing.Id);
        reloaded.IsDefault.Should().BeFalse();
    }
}
