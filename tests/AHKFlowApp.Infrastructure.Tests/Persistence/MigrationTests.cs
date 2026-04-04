using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.EntityFrameworkCore;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class MigrationTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateContext(string? databaseName = null)
    {
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
    public async Task Migrate_AppliesPendingMigrationsWithoutError()
    {
        // Arrange
        await using AppDbContext context = CreateContext("MigrationTests_Apply");

        // Act
        Func<Task> act = () => context.Database.MigrateAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }

    [Fact]
    public async Task Migrate_IsIdempotent_RunsTwiceWithoutError()
    {
        // Arrange
        await using AppDbContext context = CreateContext("MigrationTests_Idempotent");
        await context.Database.MigrateAsync();

        // Act
        Func<Task> act = () => context.Database.MigrateAsync();

        // Assert
        await act.Should().NotThrowAsync();
    }
}
