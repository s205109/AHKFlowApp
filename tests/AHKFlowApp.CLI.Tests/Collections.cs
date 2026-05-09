using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.CLI.Tests;

[CollectionDefinition("CliWebApi")]
public sealed class CliWebApiCollection : ICollectionFixture<SqlContainerFixture>;
