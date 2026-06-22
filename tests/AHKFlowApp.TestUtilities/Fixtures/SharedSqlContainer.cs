namespace AHKFlowApp.TestUtilities.Fixtures;

internal static class SharedSqlContainer
{
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static SqlContainerFixture? _container;

    // Keep this process-scoped; disposing from each xUnit collection would restart SQL between collections.
    public static async Task<string> GetConnectionStringAsync()
    {
        await Gate.WaitAsync();

        try
        {
            if (_container is null)
            {
                _container = new SqlContainerFixture();
                await _container.InitializeAsync();
            }

            return _container.ConnectionString;
        }
        catch
        {
            if (_container is not null)
            {
                await _container.DisposeAsync();
                _container = null;
            }

            throw;
        }
        finally
        {
            Gate.Release();
        }
    }
}
