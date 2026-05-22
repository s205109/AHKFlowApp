using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dashboard;

public sealed class DashboardDbFixture : MigratedDbFixture;

[CollectionDefinition("DashboardDb")]
public sealed class DashboardDbCollection : ICollectionFixture<DashboardDbFixture>;
