using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Builders;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Time.Testing; // FakeTimeProvider
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Profiles;

[Collection("ProfileDb")]
public sealed class UpdateProfileCommandHandlerTests(ProfileDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-01-01T00:00:00Z"));

    private UpdateProfileCommandHandler CreateSut(AppDbContext ctx, Guid? oid = null)
    {
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns(oid ?? _ownerOid);
        return new UpdateProfileCommandHandler(ctx, user, _clock);
    }

    [Fact]
    public async Task Updates_existing_profile()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).WithName("Work").Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        UpdateProfileCommandHandler sut = CreateSut(ctx);
        Result<ProfileDto> result = await sut.Handle(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("Work2", "h", "f", true)),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Name.Should().Be("Work2");
        result.Value.HeaderTemplate.Should().Be("h");
    }

    [Fact]
    public async Task Returns_404_for_unknown_id()
    {
        await using AppDbContext ctx = fx.CreateContext();
        UpdateProfileCommandHandler sut = CreateSut(ctx);
        Result<ProfileDto> result = await sut.Handle(
            new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto("x", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_404_for_other_users_profile()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile p = new ProfileBuilder().WithOwner(Guid.NewGuid()).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        UpdateProfileCommandHandler sut = CreateSut(ctx);
        Result<ProfileDto> result = await sut.Handle(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("x", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Returns_conflict_on_duplicate_name()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ctx.Profiles.Add(new ProfileBuilder().WithOwner(_ownerOid).WithName("A").AsDefault(true).Build());
        Profile p = new ProfileBuilder().WithOwner(_ownerOid).WithName("B").AsDefault(false).Build();
        ctx.Profiles.Add(p);
        await ctx.SaveChangesAsync();

        UpdateProfileCommandHandler sut = CreateSut(ctx);
        Result<ProfileDto> result = await sut.Handle(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("A", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Setting_IsDefault_true_clears_existing_default()
    {
        await using AppDbContext ctx = fx.CreateContext();
        Profile a = new ProfileBuilder().WithOwner(_ownerOid).WithName("A").AsDefault(true).Build();
        Profile b = new ProfileBuilder().WithOwner(_ownerOid).WithName("B").AsDefault(false).Build();
        ctx.Profiles.AddRange(a, b);
        await ctx.SaveChangesAsync();

        UpdateProfileCommandHandler sut = CreateSut(ctx);
        await sut.Handle(
            new UpdateProfileCommand(b.Id, new UpdateProfileDto("B", "", "", true)),
            CancellationToken.None);

        Profile aReloaded = await ctx.Profiles.AsNoTracking().FirstAsync(x => x.Id == a.Id);
        Profile bReloaded = await ctx.Profiles.AsNoTracking().FirstAsync(x => x.Id == b.Id);
        aReloaded.IsDefault.Should().BeFalse();
        bReloaded.IsDefault.Should().BeTrue();
    }
}
