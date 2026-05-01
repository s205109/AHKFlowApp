using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotkeys;

public sealed class HotkeyDbFixture : IAsyncLifetime
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

[CollectionDefinition("HotkeyDb")]
public sealed class HotkeyDbCollection : ICollectionFixture<HotkeyDbFixture>;
