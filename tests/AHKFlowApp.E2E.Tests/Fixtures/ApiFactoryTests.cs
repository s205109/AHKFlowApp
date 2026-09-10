using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace AHKFlowApp.E2E.Tests.Fixtures;

/// <summary>
/// Proves that <see cref="ApiFactory"/> itself gives every stack its own database.
/// </summary>
/// <remarks>
/// Both tests point a fake external server at the factory, so they need no container and no host.
/// They call <c>ApiFactory.ResolveConnectionStringAsync</c> rather than build the expected string
/// themselves. A discriminator hard-coded inside the factory would pass a test that builds its own
/// string, and fails these.
/// </remarks>
[Collection(ExclusiveTestCollection.Name)]
public sealed class ApiFactoryTests : IDisposable
{
    private const string ExternalConnectionString =
        "Server=127.0.0.1,11433;Database=master;User Id=sa;Password=not-a-secret;TrustServerCertificate=True;MultipleActiveResultSets=true";

    private const string ExternalServer = "127.0.0.1,11433";

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
        UseExternalServer();
        using ApiFactory factory = new("AHKFlowApp.E2E.Tests.A");

        // Act
        string actual = await factory.ResolveConnectionStringAsync();

        // Assert
        var builder = new SqlConnectionStringBuilder(actual);
        builder.DataSource.Should().Be(ExternalServer);
        builder.InitialCatalog.Should().Be(SqlTestDatabase.CreateName("AHKFlowApp.E2E.Tests.A"));
        builder.UserID.Should().Be("sa");
        builder.TrustServerCertificate.Should().BeTrue();
        builder.MultipleActiveResultSets.Should().BeTrue();
    }

    [Fact]
    public async Task EveryStackFixture_NamesItsOwnDatabaseOnTheOneServer()
    {
        // Arrange
        UseExternalServer();
        StackFixture[] stacks =
        [
            new StackFixtureA(),
            new StackFixtureB(),
            new StackFixtureC(),
            new StackFixtureD(),
        ];

        try
        {
            // Act
            string[] connectionStrings = await Task.WhenAll(
                stacks.Select(stack => stack.Api.ResolveConnectionStringAsync()));

            // Assert
            SqlConnectionStringBuilder[] builders =
                [.. connectionStrings.Select(connection => new SqlConnectionStringBuilder(connection))];

            builders.Select(builder => builder.DataSource).Should().AllBe(
                ExternalServer, "all four stacks share the one SQL Server");
            builders.Select(builder => builder.InitialCatalog).Should().OnlyHaveUniqueItems(
                "two stacks that name one database would write over each other's rows");
        }
        finally
        {
            foreach (StackFixture stack in stacks)
            {
                stack.Api.Dispose();
            }
        }
    }

    private static void UseExternalServer() =>
        Environment.SetEnvironmentVariable(
            SqlContainerFixture.SharedSqlConnectionStringEnvironmentVariable,
            ExternalConnectionString);
}
