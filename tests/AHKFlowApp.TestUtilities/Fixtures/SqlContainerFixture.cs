using Testcontainers.MsSql;
using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class SqlContainerFixture : IAsyncLifetime
{
    public const string SharedSqlConnectionStringEnvironmentVariable = "AHKFLOW_TEST_SQL_CONNECTION_STRING";

    public const string SqlServerImage = "mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04";

    private readonly MsSqlContainer? _container;
    private string? _connectionString;

    public SqlContainerFixture()
    {
        string? sharedSqlConnectionString = Environment.GetEnvironmentVariable(SharedSqlConnectionStringEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(sharedSqlConnectionString))
        {
            _container = new MsSqlBuilder(SqlServerImage).Build();
            return;
        }

        _connectionString = CreateTestDatabaseConnectionString(sharedSqlConnectionString);
    }

    public string ConnectionString => _connectionString
        ?? throw new InvalidOperationException("SQL test container has not been initialized.");

    public async Task InitializeAsync()
    {
        if (_container is null)
        {
            return;
        }

        await TestTimingRecorder.RecordAsync(
            nameof(SqlContainerFixture),
            typeof(SqlContainerFixture).FullName ?? nameof(SqlContainerFixture),
            "StartAsync",
            () => _container.StartAsync());

        _connectionString = CreateTestDatabaseConnectionString(_container.GetConnectionString());
    }

    public async Task DisposeAsync()
    {
        if (_container is not null)
        {
            await _container.DisposeAsync();
        }
    }

    private static string CreateTestDatabaseConnectionString(string baseConnectionString) =>
        SqlTestDatabase.CreateConnectionString(baseConnectionString, GetTestDatabaseDiscriminator());

    private static string GetTestDatabaseDiscriminator()
    {
        string? testAssemblyName = AppDomain.CurrentDomain.GetAssemblies()
            .Where(assembly => !assembly.IsDynamic)
            .Select(assembly => assembly.GetName().Name)
            .FirstOrDefault(name => name?.EndsWith(".Tests", StringComparison.Ordinal) == true);

        return testAssemblyName ?? typeof(SqlContainerFixture).FullName ?? nameof(SqlContainerFixture);
    }
}
