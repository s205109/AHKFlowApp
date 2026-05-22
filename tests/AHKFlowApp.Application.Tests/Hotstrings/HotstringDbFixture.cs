using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

public sealed class HotstringDbFixture : MigratedDbFixture;

[CollectionDefinition("HotstringDb")]
public sealed class HotstringDbCollection : ICollectionFixture<HotstringDbFixture>;
