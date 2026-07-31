using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Infrastructure.Persistence;
using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Persistence;

[Collection("SqlServer")]
public sealed class MigrationTests(SqlContainerFixture sqlFixture)
{
    private AppDbContext CreateContext(string? databaseName = null)
    {
        string connectionString = sqlFixture.ConnectionString;
        if (databaseName is not null)
        {
            var csb = new SqlConnectionStringBuilder(connectionString) { InitialCatalog = databaseName };
            connectionString = csb.ConnectionString;
        }

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

    /// <summary>
    /// Hotkeys written before the window-context columns existed must survive the upgrade and come
    /// back as global hotkeys, which fire everywhere. The rows are inserted with raw SQL, because
    /// the entity already carries columns the older schema does not have.
    /// </summary>
    [Fact]
    public async Task Migrate_ExistingHotkeys_SurviveWindowContextUpgradeAsGlobal()
    {
        // Arrange
        await using AppDbContext context = CreateContext("MigrationTests_HotkeyContext");
        IMigrator migrator = context.GetService<IMigrator>();
        await migrator.MigrateAsync("20260729151833_AddKnownShortcuts");

        var owner = Guid.NewGuid();
        var firstId = Guid.NewGuid();
        var secondId = Guid.NewGuid();
        await context.Database.ExecuteSqlAsync($"""
            INSERT INTO Hotkeys
                (Id, OwnerOid, Description, [Key], Ctrl, Alt, Shift, Win,
                 ActionKind, RunTarget, RunTargetKind, AppliesToAllProfiles, CreatedAt, UpdatedAt)
            VALUES
                ({firstId}, {owner}, 'Open Notepad', 'n', 1, 0, 0, 0,
                 2, 'notepad.exe', 0, 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET()),
                ({secondId}, {owner}, 'Open Calculator', 'c', 1, 0, 0, 0,
                 2, 'calc.exe', 0, 1, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET())
            """);

        // Act
        await context.Database.MigrateAsync();

        // Assert
        await using AppDbContext read = CreateContext("MigrationTests_HotkeyContext");
        List<Hotkey> reloaded = await read.Hotkeys
            .Where(h => h.OwnerOid == owner)
            .OrderBy(h => h.Description)
            .ToListAsync();

        reloaded.Should().HaveCount(2);
        reloaded.Should().OnlyContain(h => h.ContextMatchType == null && h.ContextValue == null);
        reloaded.Select(h => h.Description).Should().Equal("Open Calculator", "Open Notepad");
    }
}
