using Xunit;

namespace AHKFlowApp.TestUtilities.Tests;

public static class TestCollections
{
    public const string EnvironmentVariables = "EnvironmentVariables";
}

[CollectionDefinition(TestCollections.EnvironmentVariables, DisableParallelization = true)]
public sealed class EnvironmentVariableCollection;
