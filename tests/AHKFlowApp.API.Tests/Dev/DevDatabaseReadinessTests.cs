using AHKFlowApp.API;
using FluentAssertions;
using Microsoft.Data.SqlClient;
using Xunit;

namespace AHKFlowApp.API.Tests.Dev;

public sealed class DevDatabaseReadinessTests
{
    [Fact]
    public void BuildMasterProbe_RedirectsCatalogToMaster_AndReturnsTargetName()
    {
        const string connectionString =
            "Server=localhost,1433;Database=AHKFlowAppDb;User Id=sa;Password=Dev!LocalOnly_2026;TrustServerCertificate=True";

        (string MasterConnectionString, string DatabaseName)? probe =
            DevDatabaseReadiness.BuildMasterProbe(connectionString);

        probe.Should().NotBeNull();
        probe!.Value.DatabaseName.Should().Be("AHKFlowAppDb");
        new SqlConnectionStringBuilder(probe.Value.MasterConnectionString).InitialCatalog.Should().Be("master");
    }

    [Fact]
    public void BuildMasterProbe_WhenNoCatalog_ReturnsNull()
    {
        const string connectionString = "Server=localhost,1433;User Id=sa;Password=x;TrustServerCertificate=True";

        DevDatabaseReadiness.BuildMasterProbe(connectionString).Should().BeNull();
    }

    [Fact]
    public void Interpret_NoRow_IsAbsent() =>
        DevDatabaseReadiness.Interpret(null).Should().Be(DevDatabaseReadiness.DatabaseState.Absent);

    [Fact]
    public void Interpret_StateZero_IsOnline() =>
        DevDatabaseReadiness.Interpret(0).Should().Be(DevDatabaseReadiness.DatabaseState.Online);

    [Fact]
    public void Interpret_NonZeroState_IsNotReady()
    {
        DevDatabaseReadiness.Interpret(1).Should().Be(DevDatabaseReadiness.DatabaseState.NotReady); // RESTORING
        DevDatabaseReadiness.Interpret(3).Should().Be(DevDatabaseReadiness.DatabaseState.NotReady); // RECOVERY_PENDING
    }
}
