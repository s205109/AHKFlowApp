using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dev;

public sealed class DevDbFixture : IAsyncLifetime
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

[CollectionDefinition("DevDb")]
public sealed class DevDbCollection : ICollectionFixture<DevDbFixture>;
