using Microsoft.Data.SqlClient;

namespace AHKFlowApp.API;

/// <summary>
/// Development helper that waits for the target database to come ONLINE before
/// migrations run. The "Docker SQL (Recommended)" profile reuses a persisted data volume,
/// so after a container recreate SQL Server reports the <em>server</em> healthy (the compose
/// healthcheck runs <c>SELECT 1</c> against master) while the user database is still
/// recovering. EF's existence probe misreads that transient window as "does not exist"
/// and issues <c>CREATE DATABASE</c>, which then fails with error 1801.
///
/// A <c>state = 0</c> (ONLINE) row in sys.databases is not enough: there is a further
/// window where the catalog is ONLINE but a connection to it still fails with error 4060
/// ("cannot open database") because recovery is not yet accepting connections — and that
/// 4060 is exactly what EF reads as "does not exist". So once the catalog is ONLINE we also
/// open the <em>target</em> database (mirroring EF's own probe) and only return once that
/// succeeds. A genuinely absent database (no sys.databases row) returns immediately so
/// MigrateAsync is free to create it.
/// </summary>
internal static class DevDatabaseReadiness
{
    internal enum DatabaseState
    {
        Online,   // state = 0: ready to migrate
        Absent,   // no row: first run, let MigrateAsync create it
        NotReady  // exists but recovering/restoring/etc.
    }

    // Pure: derive a master connection string + the target database name from an app
    // connection string. Returns null when no catalog is set (nothing to wait for).
    internal static (string MasterConnectionString, string DatabaseName)? BuildMasterProbe(string connectionString)
    {
        var builder = new SqlConnectionStringBuilder(connectionString);
        string database = builder.InitialCatalog;
        if (string.IsNullOrWhiteSpace(database))
        {
            return null;
        }

        builder.InitialCatalog = "master";
        return (builder.ConnectionString, database);
    }

    // Pure: map a sys.databases.state value (null = no row) to our readiness model.
    internal static DatabaseState Interpret(int? state) => state switch
    {
        null => DatabaseState.Absent,
        0 => DatabaseState.Online,
        _ => DatabaseState.NotReady
    };

    internal static async Task WaitForDatabaseOnlineAsync(
        string connectionString,
        int maxAttempts = 60,
        TimeSpan? delay = null,
        CancellationToken cancellationToken = default)
    {
        if (BuildMasterProbe(connectionString) is not { } probe)
        {
            return;
        }

        (string masterConnectionString, string database) = probe;
        TimeSpan pollDelay = delay ?? TimeSpan.FromSeconds(1);

        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                DatabaseState state = await QueryStateAsync(masterConnectionString, database, cancellationToken);
                if (state is DatabaseState.Absent)
                {
                    return;
                }

                if (state is DatabaseState.Online)
                {
                    // ONLINE in the catalog still isn't openable during the tail of recovery
                    // (error 4060). Confirm a real connection to the target succeeds — that is
                    // what EF's existence probe does — before letting migration run.
                    if (await CanOpenTargetAsync(connectionString, cancellationToken))
                    {
                        return;
                    }

                    Console.WriteLine($"[DevDatabaseReadiness] '{database}' is ONLINE but not yet accepting connections (attempt {attempt}/{maxAttempts}); waiting...");
                }
                else
                {
                    Console.WriteLine($"[DevDatabaseReadiness] '{database}' is recovering (attempt {attempt}/{maxAttempts}); waiting...");
                }
            }
            catch (SqlException ex)
            {
                Console.WriteLine($"[DevDatabaseReadiness] SQL Server not reachable yet (attempt {attempt}/{maxAttempts}): {ex.Message}");
            }

            await Task.Delay(pollDelay, cancellationToken);
        }

        Console.Error.WriteLine(
            $"[DevDatabaseReadiness] Timed out waiting for '{database}' to come online; continuing and letting migration surface any error.");
    }

    // Mirror EF's existence probe: open the target database itself and run a trivial query.
    // Returns false on any SqlException (4060 during recovery, transient warm-up, etc.) so the
    // caller keeps waiting instead of letting EF misread the failure as "database missing".
    private static async Task<bool> CanOpenTargetAsync(string connectionString, CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using SqlCommand command = connection.CreateCommand();
            command.CommandText = "SELECT 1";
            await command.ExecuteScalarAsync(cancellationToken);
            return true;
        }
        catch (SqlException)
        {
            return false;
        }
    }

    private static async Task<DatabaseState> QueryStateAsync(
        string masterConnectionString,
        string database,
        CancellationToken cancellationToken)
    {
        await using var connection = new SqlConnection(masterConnectionString);
        await connection.OpenAsync(cancellationToken);

        await using SqlCommand command = connection.CreateCommand();
        command.CommandText = "SELECT state FROM sys.databases WHERE name = @db";
        command.Parameters.Add(new SqlParameter("@db", database));

        object? result = await command.ExecuteScalarAsync(cancellationToken);
        int? state = result is null or DBNull ? null : Convert.ToInt32(result);
        return Interpret(state);
    }
}
