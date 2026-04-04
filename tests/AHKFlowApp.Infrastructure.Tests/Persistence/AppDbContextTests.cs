using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class AppDbContextTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateContext(string? databaseName = null)
    {
        // Use a unique database name to isolate from MigrationTests
        // (EnsureCreated and Migrate conflict if they hit the same DB)
        string connectionString = sqlFixture.ConnectionString;
        if (databaseName is not null)
            connectionString = connectionString.Replace("master", databaseName);

        DbContextOptions<AppDbContext> options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlServer(connectionString,
                sql => sql.EnableRetryOnFailure())
            .Options;

        return new AppDbContext(options);
    }

    [Fact]
    public async Task CanConnect_WhenDatabaseExists_ReturnsTrue()
    {
        // Arrange
        await using AppDbContext context = CreateContext("AppDbContextTests_CanConnect");
        await context.Database.EnsureCreatedAsync();

        // Act
        bool canConnect = await context.Database.CanConnectAsync();

        // Assert
        canConnect.Should().BeTrue();
    }

    [Fact]
    public async Task EnsureCreated_AppliesSchemaWithoutError()
    {
        // Arrange
        await using AppDbContext context = CreateContext("AppDbContextTests_EnsureCreated");

        // Act
        Func<Task> act = () => context.Database.EnsureCreatedAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }
}
