using AHKFlowApp.TestUtilities.Fixtures;
using Xunit;

namespace AHKFlowApp.API.Tests;

[CollectionDefinition("WebApi")]
public sealed class WebApiCollection : ICollectionFixture<SqlContainerFixture>;
