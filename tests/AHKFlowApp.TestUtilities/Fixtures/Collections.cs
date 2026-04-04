using Xunit;

namespace AHKFlowApp.TestUtilities.Fixtures;

[CollectionDefinition("SqlServer")]
public sealed class SqlServerCollection : ICollectionFixture<SqlContainerFixture>;

[CollectionDefinition("WebApi")]
public sealed class WebApiCollection : ICollectionFixture<SqlContainerFixture>;
