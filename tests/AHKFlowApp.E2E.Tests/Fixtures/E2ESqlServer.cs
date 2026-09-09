using AHKFlowApp.TestUtilities.Fixtures;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Hands every stack in this test process one SQL Server to work on.
/// </summary>
/// <remarks>
/// The stacks each name their own database on this one server, so the process starts at most one
/// container however many stacks run. Under scripts/test-fast.ps1 there is no container at all:
/// the script starts one and passes its connection string in the environment.
///
/// The string this returns is a server address. It carries whatever catalog the source set, and
/// the caller always replaces it through SqlTestDatabase.CreateConnectionString.
/// </remarks>
internal static class E2ESqlServer
{
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static SharedSqlServerFixture? _fixture;

    public static async Task<string> GetConnectionStringAsync()
    {
        string? shared = Environment.GetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(shared))
        {
            return shared;
        }

        await Gate.WaitAsync();
        try
        {
            if (_fixture is null)
            {
                SharedSqlServerFixture fixture = new();
                await fixture.InitializeAsync();
                _fixture = fixture;
            }

            return _fixture.ConnectionString;
        }
        finally
        {
            Gate.Release();
        }
    }
}
