using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests;

[CollectionDefinition("SqlServer")]
public sealed class SqlServerCollection : ICollectionFixture<SqlContainerFixture>;
