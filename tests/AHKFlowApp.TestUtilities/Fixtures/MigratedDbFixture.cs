using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// Starts a SQL Server container and applies all EF Core migrations once per xUnit collection.
/// Derive a sealed per-suite class so each collection gets an isolated database.
/// </summary>
public abstract class MigratedDbFixture : IAsyncLifetime
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
