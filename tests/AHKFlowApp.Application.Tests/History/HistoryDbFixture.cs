using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Application.Tests.History;

public sealed class HistoryDbFixture : MigratedDbFixture;

[CollectionDefinition("HistoryDb")]
public sealed class HistoryDbCollection : ICollectionFixture<HistoryDbFixture>;
