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
[Trait("Category", "Integration")]
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
        Result<ProfileDto> result = await sut.ExecuteAsync(
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
        Result<ProfileDto> result = await sut.ExecuteAsync(
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
        Result<ProfileDto> result = await sut.ExecuteAsync(
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
        Result<ProfileDto> result = await sut.ExecuteAsync(
            new UpdateProfileCommand(p.Id, new UpdateProfileDto("A", "", "", false)),
            CancellationToken.None);
        result.Status.Should().Be(ResultStatus.Conflict);
    }

    [Fact]
    public async Task Returns_unauthorized_when_no_oid()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser user = Substitute.For<ICurrentUser>();
        user.Oid.Returns((Guid?)null);
        var sut = new UpdateProfileCommandHandler(ctx, user, _clock);

        Result<ProfileDto> result = await sut.ExecuteAsync(
            new UpdateProfileCommand(Guid.NewGuid(), new UpdateProfileDto("x", "", "", false)),
            CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    // Backlog 166: the handler failed in a new context, which is what every API request gets.
    // The old version of this test shared one context with the seed, and so passed against the bug.
    [Fact]
    public async Task Setting_IsDefault_true_in_a_new_context_leaves_exactly_one_default()
    {
        (Profile _, Profile b) = await SeedAsync();

        await using AppDbContext ctx = fx.CreateContext();
        Result<ProfileDto> result = await CreateSut(ctx).ExecuteAsync(
            new UpdateProfileCommand(b.Id, new UpdateProfileDto("B", "", "", true)),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        (await DefaultIdsAsync()).Should().Equal(b.Id);
    }

    // Backlog 166: the execution strategy runs the delegate again after a transient failure.
    // The second attempt must start from the database, not from what the first attempt tracked.
    [Fact]
    public async Task Setting_IsDefault_true_succeeds_when_a_transient_failure_forces_a_retry()
    {
        (Profile _, Profile b) = await SeedAsync();
        var failure = new TransientFailureInterceptor();
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(fx.ConnectionString, sql => sql.EnableRetryOnFailure(
                1, TimeSpan.FromSeconds(1), [TransientFailureInterceptor.ErrorNumber]))
            .AddInterceptors(failure)
            .Options;

        await using var ctx = new AppDbContext(options);
        Result<ProfileDto> result = await CreateSut(ctx).ExecuteAsync(
            new UpdateProfileCommand(b.Id, new UpdateProfileDto("B", "", "", true)),
            CancellationToken.None);

        failure.FailuresInjected.Should().Be(1);
        result.IsSuccess.Should().BeTrue();   // a success after one injected failure means a second attempt ran
        (await DefaultIdsAsync()).Should().Equal(b.Id);
    }

    // Backlog 166: a default index violation read as a name collision.
    [Fact]
    public async Task A_default_set_at_the_same_time_returns_the_default_message_and_saves_nothing()
    {
        (Profile a, Profile b) = await SeedAsync();

        await using AppDbContext ctx = fx.CreateContext(new RivalDefaultInterceptor(_ownerOid));
        Result<ProfileDto> result = await CreateSut(ctx).ExecuteAsync(
            new UpdateProfileCommand(b.Id, new UpdateProfileDto("B2", "", "", true)),
            CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Conflict);
        result.Errors.Should().Equal(ProfileDefaults.ChangedAtTheSameTime);
        (await DefaultIdsAsync()).Should().Equal(a.Id);
        await using AppDbContext check = fx.CreateContext();
        (await check.Profiles.AsNoTracking().Where(p => p.OwnerOid == _ownerOid).Select(p => p.Name).ToListAsync())
            .Should().BeEquivalentTo("A", "B");
    }

    private async Task<(Profile A, Profile B)> SeedAsync()
    {
        await using AppDbContext seed = fx.CreateContext();
        Profile a = new ProfileBuilder().WithOwner(_ownerOid).WithName("A").AsDefault(true).Build();
        Profile b = new ProfileBuilder().WithOwner(_ownerOid).WithName("B").AsDefault(false).Build();
        seed.Profiles.AddRange(a, b);
        await seed.SaveChangesAsync();
        return (a, b);
    }

    private async Task<List<Guid>> DefaultIdsAsync()
    {
        await using AppDbContext ctx = fx.CreateContext();
        return await ctx.Profiles.AsNoTracking()
            .Where(p => p.OwnerOid == _ownerOid && p.IsDefault)
            .Select(p => p.Id)
            .ToListAsync();
    }
}
