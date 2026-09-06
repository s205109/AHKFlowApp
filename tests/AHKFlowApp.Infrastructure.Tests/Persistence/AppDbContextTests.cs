using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

public sealed class AppDbContextTests(SharedSqlServerFixture sqlFixture)
    : IClassFixture<SharedSqlServerFixture>
{
    // databaseName is required, and every caller passes a name unique to its own test. Two
    // reasons. EnsureCreated and Migrate fight each other when they hit the same database, and
    // classes holding SharedSqlServerFixture run at the same time. A default would let a new
    // call share the assembly database with every other class silently.
    private AppDbContext CreateContext(string databaseName)
    {
        var csb = new SqlConnectionStringBuilder(sqlFixture.ConnectionString) { InitialCatalog = databaseName };
        string connectionString = csb.ConnectionString;

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
        Func<Task> act = async () => await context.Database.EnsureCreatedAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }
}
