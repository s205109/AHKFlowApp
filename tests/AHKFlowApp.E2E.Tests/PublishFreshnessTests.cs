using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

[Collection(E2ETestCollection.Name)]
public sealed class PublishFreshnessTests(StackFixture fixture)
{
    // Directory.GetFiles has a legacy quirk where a three-character extension also matches
    // longer ones. ".wasm" is four characters and ".js" is two, so both patterns below match
    // exactly. PublishedFramework_AfterAnyE2ERun_HoldsNoCompressedSiblings covers the ".br"
    // and ".gz" siblings, so no pattern here has to exclude them.
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

    // The E2E publish passes -p:CompressionEnabled=false. E2EPublishTargetTests asserts the flag
    // is on the command line, which is a fast diagnostic but not proof. This test asserts the
    // outcome the flag exists for, so the publish stays uncompressed even if the SDK stops
    // honoring the property or another setting turns compression back on.
    [Fact]
    public void PublishedWwwroot_AfterAnyE2ERun_HoldsNoCompressedSiblings()
    {
        // Act
        string[] compressed =
        [
            .. Directory.EnumerateFiles(fixture.PublishedWwwroot, "*", SearchOption.AllDirectories)
                .Where(path => Path.GetExtension(path) is ".br" or ".gz")
                .Select(path => Path.GetRelativePath(fixture.PublishedWwwroot, path))
                .Order(StringComparer.Ordinal)
        ];

        // Assert
        compressed.Should().BeEmpty(
            "nothing in the E2E stack reads a .br or .gz sibling, so writing them is wasted publish time");
    }
}
