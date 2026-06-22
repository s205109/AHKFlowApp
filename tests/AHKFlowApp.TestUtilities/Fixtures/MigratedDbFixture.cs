using AHKFlowApp.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// Applies all EF Core migrations once per xUnit collection.
/// Derive a sealed per-suite class so each collection gets an isolated database.
/// </summary>
public abstract class MigratedDbFixture : IAsyncLifetime
{
    private string? _connectionString;

    public string ConnectionString =>
        _connectionString ?? throw new InvalidOperationException("The fixture has not been initialized.");

    public async Task InitializeAsync()
    {
        string containerConnectionString = await SharedSqlContainer.GetConnectionStringAsync();
        _connectionString = SqlTestDatabase.CreateConnectionString(containerConnectionString, GetType());

        await TestTimingRecorder.RecordAsync(
            nameof(MigratedDbFixture),
            GetType().FullName ?? GetType().Name,
            "MigrateAsync",
            async () =>
            {
                await using AppDbContext ctx = CreateContext();
                await ctx.Database.MigrateAsync();
            });
    }

    public Task DisposeAsync() => Task.CompletedTask;

    public AppDbContext CreateContext()
    {
        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(ConnectionString)
            .Options;
        return new AppDbContext(options);
    }
}
