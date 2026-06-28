using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

public sealed class ApiFactoryTests : IDisposable
{
    private readonly string? _previousConnectionString = Environment.GetEnvironmentVariable(
        SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable);

    public void Dispose() =>
        Environment.SetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable,
            _previousConnectionString);

    [Fact]
    public void ConnectionString_WhenExternalConnectionConfigured_UsesPerAssemblyDatabase()
    {
        // Arrange
        const string externalConnectionString = "Server=127.0.0.1,11433;Database=master;User Id=sa;Password=not-a-secret;TrustServerCertificate=True;MultipleActiveResultSets=true";
        Environment.SetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable,
            externalConnectionString);

        // Act
        var factory = new ApiFactory();

        // Assert
        var builder = new SqlConnectionStringBuilder(factory.ConnectionString);
        builder.DataSource.Should().Be("127.0.0.1,11433");
        builder.InitialCatalog.Should().Be(SqlTestDatabase.CreateName("AHKFlowApp.E2E.Tests"));
        builder.UserID.Should().Be("sa");
        builder.TrustServerCertificate.Should().BeTrue();
        builder.MultipleActiveResultSets.Should().BeTrue();
    }
}
