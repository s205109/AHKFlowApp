using AHKFlowApp.E2E.Tests.Fixtures;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class E2ETestCollection : ICollectionFixture<StackFixture>
{
    public const string Name = "E2E";
}
