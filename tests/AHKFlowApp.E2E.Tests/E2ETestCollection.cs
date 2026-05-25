using Xunit;

namespace AHKFlowApp.E2E.Tests;

[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class E2ETestCollection
{
    public const string Name = "E2E";
}
