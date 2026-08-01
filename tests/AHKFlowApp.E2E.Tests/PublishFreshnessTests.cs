using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class PublishFreshnessTests(StackFixture fixture)
{
    // Directory.GetFiles has a legacy quirk where a three-character extension also matches
    // longer ones. ".wasm" is four characters and ".js" is two, so both patterns below match
    // exactly, and the ".br" and ".gz" siblings are not counted.
    [Theory]
    [InlineData("AHKFlowApp.UI.Blazor.*.wasm")]
    [InlineData("dotnet.native.*.js")]
    [InlineData("dotnet.runtime.*.js")]
    public void PublishedFramework_AfterAnyE2ERun_HoldsExactlyOneCopyOfEachBootAsset(string pattern)
    {
        // Arrange
        string frameworkDirectory = Path.Combine(fixture.PublishedWwwroot, "_framework");

        // Act
        string[] matches = Directory.GetFiles(frameworkDirectory, pattern);

        // Assert
        matches.Should().ContainSingle(
            "the E2E publish destination must hold exactly one '{0}', or a stale copy can be served",
            pattern);
    }
}
