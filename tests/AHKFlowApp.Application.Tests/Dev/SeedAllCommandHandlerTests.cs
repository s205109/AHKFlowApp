using AHKFlowApp.Application;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Infrastructure.Persistence;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dev;

[Collection("DevDb")]
[Trait("Category", "Integration")]
public sealed class SeedAllCommandHandlerTests(DevDbFixture fx)
{
    private readonly Guid _ownerOid = Guid.NewGuid();
    private readonly FakeTimeProvider _clock = new(DateTimeOffset.Parse("2026-05-19T12:00:00Z"));
    private readonly AppEnvironment _devEnv = new(IsDevelopment: true);

    private ICurrentUser User()
    {
        ICurrentUser u = Substitute.For<ICurrentUser>();
        u.Oid.Returns(_ownerOid);
        return u;
    }

    private ServiceProvider BuildProvider(IAppDbContext db, ICurrentUser? user = null, AppEnvironment? appEnv = null)
    {
        ServiceCollection services = new();
        services.AddLogging();
        services.AddSingleton(db);
        services.AddSingleton(user ?? User());
        services.AddSingleton<TimeProvider>(_clock);
        services.AddSingleton(appEnv ?? _devEnv);
        services.AddApplication();
        return services.BuildServiceProvider();
    }

    [Fact]
    public async Task SeedAll_Inserts_AllThree_Inside_OneTransaction()
    {
        await using AppDbContext ctx = fx.CreateContext();
        await using ServiceProvider sp = BuildProvider(ctx);

        Result<SeedAllResultDto> result = await sp.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>()
            .ExecuteAsync(new SeedAllCommand(Reset: false), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoriesCount.Should().Be(8);
        result.Value.HotstringsCount.Should().Be(HotstringSeedSamples.All.Length);
        result.Value.HotkeysCount.Should().Be(17);

        await using AppDbContext verify = fx.CreateContext();
        // Every sample carries exactly one category, so the junction count tracks the sample count.
        (await verify.HotstringCategories.CountAsync(hc => hc.Hotstring.OwnerOid == _ownerOid)).Should().Be(HotstringSeedSamples.All.Length);
        (await verify.HotkeyCategories.CountAsync(hc => hc.Hotkey.OwnerOid == _ownerOid)).Should().Be(17);
    }

    [Fact]
    public async Task SeedAll_Reset_ClearsAll_AndReseeds()
    {
        await using (AppDbContext ctx1 = fx.CreateContext())
        await using (ServiceProvider sp1 = BuildProvider(ctx1))
        {
            await sp1.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>()
                .ExecuteAsync(new SeedAllCommand(Reset: false), CancellationToken.None);
        }

        await using AppDbContext ctx2 = fx.CreateContext();
        await using ServiceProvider sp2 = BuildProvider(ctx2);

        Result<SeedAllResultDto> result = await sp2.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>()
            .ExecuteAsync(new SeedAllCommand(Reset: true), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.CategoriesCount.Should().Be(8);
        result.Value.HotstringsCount.Should().Be(HotstringSeedSamples.All.Length);
        result.Value.HotkeysCount.Should().Be(17);
    }

    [Fact]
    public async Task SeedAll_RollsBack_OnInnerFailure_LeavesNoRows()
    {
        await using AppDbContext realCtx = fx.CreateContext();
        IAppDbContext failingDb = new ThrowOnNthSaveDbContext(realCtx, failOnCall: 2);
        await using ServiceProvider sp = BuildProvider(failingDb);
        IUseCase<SeedAllCommand, Result<SeedAllResultDto>> useCase =
            sp.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>();

        Func<Task> act = async () => await useCase.ExecuteAsync(new SeedAllCommand(Reset: false), CancellationToken.None);

        await act.Should().ThrowAsync<InvalidOperationException>();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.Categories.CountAsync(c => c.OwnerOid == _ownerOid)).Should().Be(0);
        (await verify.Hotstrings.CountAsync(h => h.OwnerOid == _ownerOid)).Should().Be(0);
        (await verify.Hotkeys.CountAsync(h => h.OwnerOid == _ownerOid)).Should().Be(0);
    }

    [Fact]
    public async Task SeedAll_ReturnsNotFound_When_NotInDevelopment()
    {
        await using AppDbContext ctx = fx.CreateContext();
        await using ServiceProvider sp = BuildProvider(ctx, appEnv: new AppEnvironment(IsDevelopment: false));

        Result<SeedAllResultDto> result = await sp.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>()
            .ExecuteAsync(new SeedAllCommand(Reset: false), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task SeedAll_PropagatesUnauthorized_WhenInnerStepReturnsUnauthorized()
    {
        await using AppDbContext ctx = fx.CreateContext();
        ICurrentUser noUser = Substitute.For<ICurrentUser>();
        noUser.Oid.Returns((Guid?)null);
        await using ServiceProvider sp = BuildProvider(ctx, user: noUser);

        Result<SeedAllResultDto> result = await sp.GetRequiredService<IUseCase<SeedAllCommand, Result<SeedAllResultDto>>>()
            .ExecuteAsync(new SeedAllCommand(Reset: false), CancellationToken.None);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
