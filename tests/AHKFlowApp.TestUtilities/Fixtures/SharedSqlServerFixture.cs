using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

/// <summary>
/// Hands one test class the shared SQL Server's connection string.
/// </summary>
/// <remarks>
/// Use it as an <c>IClassFixture</c>, not a collection fixture. A class with no Collection
/// attribute is its own xUnit Collection, so several classes holding this fixture run at the
/// same time. Every instance goes through <c>SharedSqlContainer</c>, so the assembly starts at
/// most one container however many classes use it.
///
/// Nothing is disposed here. <c>SharedSqlContainer</c> holds the container for the life of the
/// process, the same way <c>MigratedDbFixture</c> does. Under scripts/test-fast.ps1 there is no
/// container to dispose: the script owns one and passes its connection string in the environment.
/// </remarks>
public sealed class SharedSqlServerFixture : IAsyncLifetime
{
    private string? _connectionString;

    public string ConnectionString => _connectionString
        ?? throw new InvalidOperationException("The shared SQL Server fixture has not been initialized.");

    public async Task InitializeAsync() =>
        _connectionString = await SharedSqlContainer.GetConnectionStringAsync();

    public Task DisposeAsync() => Task.CompletedTask;
}
