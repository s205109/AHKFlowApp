using AHKFlowApp.Application.Commands.Preferences;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Preferences;
using AHKFlowApp.Application.Tests.Hotstrings;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Ardalis.Result;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Preferences;

public sealed class PreferenceDbFixture : IAsyncLifetime
{
    private readonly SqlContainerFixture _sql = new();

    public string ConnectionString => _sql.ConnectionString;

    public async Task InitializeAsync()
    {
        await _sql.InitializeAsync();
        await using AppDbContext ctx = CreateContext();
        await ctx.Database.MigrateAsync();
    }

    public Task DisposeAsync() => _sql.DisposeAsync();

    public AppDbContext CreateContext()
    {
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(ConnectionString)
            .Options;
        return new AppDbContext(options);
    }
}

[CollectionDefinition("PreferenceDb")]
public sealed class PreferenceDbCollection : ICollectionFixture<PreferenceDbFixture>;

[Collection("PreferenceDb")]
public sealed class PreferenceHandlerTests(PreferenceDbFixture fx)
{
    private readonly TimeProvider _clock = TimeProvider.System;

    // ── GetUserPreferenceQueryHandler ────────────────────────────────────────

    [Fact]
    public async Task Get_WhenNoRowExists_ReturnsNotFound()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new GetUserPreferenceQueryHandler(db, CurrentUserHelper.For(Guid.NewGuid()));

        Result<UserPreferenceDto> result = await handler.Handle(new GetUserPreferenceQuery(), default);

        result.Status.Should().Be(ResultStatus.NotFound);
    }

    [Fact]
    public async Task Get_WhenRowExists_ReturnsSavedValues()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            var pref = UserPreference.CreateDefault(owner, _clock);
            pref.Update(50, true, _clock);
            seed.UserPreferences.Add(pref);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new GetUserPreferenceQueryHandler(db, CurrentUserHelper.For(owner));

        Result<UserPreferenceDto> result = await handler.Handle(new GetUserPreferenceQuery(), default);

        result.IsSuccess.Should().BeTrue();
        result.Value.RowsPerPage.Should().Be(50);
        result.Value.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task Get_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new GetUserPreferenceQueryHandler(db, CurrentUserHelper.For(null));

        Result<UserPreferenceDto> result = await handler.Handle(new GetUserPreferenceQuery(), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }

    // ── UpdateUserPreferenceCommandHandler ───────────────────────────────────

    [Fact]
    public async Task Update_WhenNoRowExists_CreatesRowAndReturnsSuccess()
    {
        var owner = Guid.NewGuid();
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateUserPreferenceCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new UpdateUserPreferenceCommand(new UpdateUserPreferenceDto(25, true));

        Result<UserPreferenceDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.RowsPerPage.Should().Be(25);
        result.Value.DarkMode.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        (await verify.UserPreferences.CountAsync(p => p.OwnerOid == owner)).Should().Be(1);
    }

    [Fact]
    public async Task Update_WhenRowExists_UpdatesValuesAndReturnsSuccess()
    {
        var owner = Guid.NewGuid();
        await using (AppDbContext seed = fx.CreateContext())
        {
            var pref = UserPreference.CreateDefault(owner, _clock);
            pref.Update(10, false, _clock);
            seed.UserPreferences.Add(pref);
            await seed.SaveChangesAsync();
        }

        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateUserPreferenceCommandHandler(db, CurrentUserHelper.For(owner), _clock);
        var cmd = new UpdateUserPreferenceCommand(new UpdateUserPreferenceDto(100, true));

        Result<UserPreferenceDto> result = await handler.Handle(cmd, default);

        result.IsSuccess.Should().BeTrue();
        result.Value.RowsPerPage.Should().Be(100);
        result.Value.DarkMode.Should().BeTrue();

        await using AppDbContext verify = fx.CreateContext();
        UserPreference saved = await verify.UserPreferences.SingleAsync(p => p.OwnerOid == owner);
        saved.RowsPerPage.Should().Be(100);
        saved.DarkMode.Should().BeTrue();
    }

    [Fact]
    public async Task Update_WhenNoOid_ReturnsUnauthorized()
    {
        await using AppDbContext db = fx.CreateContext();
        var handler = new UpdateUserPreferenceCommandHandler(db, CurrentUserHelper.For(null), _clock);

        Result<UserPreferenceDto> result = await handler.Handle(
            new UpdateUserPreferenceCommand(new UpdateUserPreferenceDto(25, false)), default);

        result.Status.Should().Be(ResultStatus.Unauthorized);
    }
}
