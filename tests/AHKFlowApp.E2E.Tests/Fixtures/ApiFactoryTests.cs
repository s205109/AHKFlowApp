using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

[Collection(ExclusiveTestCollection.Name)]
public sealed class ApiFactoryTests : IDisposable
{
    private readonly string? _previousConnectionString = Environment.GetEnvironmentVariable(
        SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable);

    public void Dispose() =>
        Environment.SetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable,
            _previousConnectionString);

    [Fact]
    public async Task ConnectionString_WhenExternalConnectionConfigured_UsesPerGroupDatabase()
    {
        // Arrange
        const string externalConnectionString = "Server=127.0.0.1,11433;Database=master;User Id=sa;Password=not-a-secret;TrustServerCertificate=True;MultipleActiveResultSets=true";
        Environment.SetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable,
            externalConnectionString);

        // Act
        string server = await E2ESqlServer.GetConnectionStringAsync();
        string actual = SqlTestDatabase.CreateConnectionString(server, "AHKFlowApp.E2E.Tests.A");

        // Assert
        var builder = new SqlConnectionStringBuilder(actual);
        builder.DataSource.Should().Be("127.0.0.1,11433");
        builder.InitialCatalog.Should().Be(SqlTestDatabase.CreateName("AHKFlowApp.E2E.Tests.A"));
        builder.UserID.Should().Be("sa");
        builder.TrustServerCertificate.Should().BeTrue();
        builder.MultipleActiveResultSets.Should().BeTrue();
    }
}
