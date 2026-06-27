using AHKFlowApp.TestUtilities.Fixtures;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace AHKFlowApp.Domain.Tests.Fixtures;

public sealed class SqlTestDatabaseTests
{
    [Fact]
    public void CreateName_SameFixtureType_ReturnsStableName()
    {
        // Act
        string first = SqlTestDatabase.CreateName(typeof(AlphaDbFixture));
        string second = SqlTestDatabase.CreateName(typeof(AlphaDbFixture));

        // Assert
        second.Should().Be(first);
    }

    [Fact]
    public void CreateName_DifferentFixtureTypes_ReturnsDifferentNames()
    {
        // Act
        string alpha = SqlTestDatabase.CreateName(typeof(AlphaDbFixture));
        string beta = SqlTestDatabase.CreateName(typeof(BetaDbFixture));

        // Assert
        beta.Should().NotBe(alpha);
    }

    [Fact]
    public void CreateName_FixtureType_ReturnsSqlSafeName()
    {
        // Act
        string databaseName = SqlTestDatabase.CreateName(typeof(AlphaDbFixture));

        // Assert
        databaseName.Should().StartWith("AHKFlowTest_");
        databaseName.Should().MatchRegex("^[A-Za-z0-9_]+$");
        databaseName.Length.Should().BeLessThanOrEqualTo(128);
    }

    [Fact]
    public void CreateConnectionString_FixtureType_ReplacesInitialCatalog()
    {
        // Arrange
        const string baseConnectionString = "Server=localhost,1433;Database=master;User Id=sa;Password=not-a-secret;TrustServerCertificate=True";
        string expectedDatabaseName = SqlTestDatabase.CreateName(typeof(AlphaDbFixture));

        // Act
        string connectionString = SqlTestDatabase.CreateConnectionString(baseConnectionString, typeof(AlphaDbFixture));

        // Assert
        var builder = new SqlConnectionStringBuilder(connectionString);
        builder.DataSource.Should().Be("localhost,1433");
        builder.InitialCatalog.Should().Be(expectedDatabaseName);
        builder.UserID.Should().Be("sa");
        builder.TrustServerCertificate.Should().BeTrue();
    }

    [Fact]
    public void CreateConnectionString_Discriminator_ReplacesInitialCatalog()
    {
        // Arrange
        const string baseConnectionString = "Server=localhost,1433;Database=master;User Id=sa;Password=not-a-secret;TrustServerCertificate=True";
        string expectedDatabaseName = SqlTestDatabase.CreateName("AHKFlowApp.API.Tests");

        // Act
        string connectionString = SqlTestDatabase.CreateConnectionString(baseConnectionString, "AHKFlowApp.API.Tests");

        // Assert
        var builder = new SqlConnectionStringBuilder(connectionString);
        builder.InitialCatalog.Should().Be(expectedDatabaseName);
        builder.InitialCatalog.Should().NotBe("master");
    }

    private sealed class AlphaDbFixture : MigratedDbFixture;

    private sealed class BetaDbFixture : MigratedDbFixture;
}
