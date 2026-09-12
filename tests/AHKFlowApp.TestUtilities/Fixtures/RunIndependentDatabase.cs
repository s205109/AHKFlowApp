using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.DependencyInjection;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// Drops a test database before the test builds it, so the test starts from the state it needs
/// whatever an earlier run left behind. CONTEXT.md calls that property a Run-independent test, and
/// docs/adr/0015-sql-tests-are-run-independent.md records why the drop happens first and not last.
/// </summary>
/// <remarks>
/// A test that reaches a migration before the newest one goes through
/// <see cref="DropThenMigrateToAsync"/> and never calls IMigrator itself.
/// tests/RunIndependentSqlTests.Tests.ps1 fails a test file that reaches one by any other route.
/// </remarks>
public static class RunIndependentDatabase
{
    /// <summary>
    /// Drops the context's database when it exists, and does nothing when it does not. A test that
    /// builds its own schema calls this first, so it never reads a schema an earlier run created.
    /// </summary>
    public static async Task DropAsync(
        DbContext context,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);

        await context.Database.EnsureDeletedAsync(cancellationToken);
    }

    /// <summary>
    /// Drops the context's database, then applies migrations up to and including
    /// <paramref name="targetMigration"/>.
    /// </summary>
    /// <param name="targetMigration">
    /// The migration to stop at, by name, for example AddHotstringDelivery. The full identifier
    /// with its timestamp prefix also works.
    /// </param>
    /// <remarks>
    /// The drop is what makes the migration run forwards. Against a database already at the newest
    /// migration, EF Core reads a target as a request to migrate down, and the HotkeyTypedActions
    /// migration throws rather than reverting.
    /// </remarks>
    public static async Task DropThenMigrateToAsync(
        DbContext context,
        string targetMigration,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentException.ThrowIfNullOrWhiteSpace(targetMigration);

        await context.Database.EnsureDeletedAsync(cancellationToken);

        IMigrator migrator = ((IInfrastructure<IServiceProvider>)context).Instance
            .GetRequiredService<IMigrator>();
        await migrator.MigrateAsync(targetMigration, cancellationToken);
    }
}
