using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

public sealed class ApiTestFixture : IAsyncLifetime
{
    private readonly SqlContainerFixture _sqlFixture = new();
    private CustomWebApplicationFactory? _factory;

    public SqlContainerFixture SqlFixture => _sqlFixture;

    public CustomWebApplicationFactory Factory =>
        _factory ?? throw new InvalidOperationException("The API test fixture has not been initialized.");

    public async Task InitializeAsync()
    {
        await _sqlFixture.InitializeAsync();
        _factory = new CustomWebApplicationFactory(_sqlFixture);
    }

    public async Task DisposeAsync()
    {
        if (_factory is not null)
            await _factory.DisposeAsync();

        await _sqlFixture.DisposeAsync();
    }
}
