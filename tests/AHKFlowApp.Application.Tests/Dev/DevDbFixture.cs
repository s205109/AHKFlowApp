using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Dev;

public sealed class DevDbFixture : MigratedDbFixture;

[CollectionDefinition("DevDb")]
public sealed class DevDbCollection : ICollectionFixture<DevDbFixture>;
