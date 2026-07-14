using AHKFlowApp.TestUtilities.Fixtures;
using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class RawDefinitionTests
{
    public static TheoryData<string> FixtureNames()
    {
        TheoryData<string> data = [];
        foreach (ScriptToRawFixture f in ScriptToRawFixtures.All)
            data.Add(f.Name);
        return data;
    }

    [Theory]
    [MemberData(nameof(FixtureNames))]
    public void Compose_MatchesServerComposer(string fixtureName)
    {
        ScriptToRawFixture f = ScriptToRawFixtures.All.Single(x => x.Name == fixtureName);

        string composed = RawDefinition.Compose(
            f.Trigger, f.Body,
            f.IsEndingCharacterRequired, f.IsTriggerInsideWord,
            f.IsCaseSensitive, f.OmitEndingCharacter);

        composed.Should().Be(f.ExpectedRawDefinition);
    }

    [Fact]
    public void Decompose_BraceBody_ExtractsTriggerAndBody()
    {
        RawDecomposition result = RawDefinition.Decompose(":*:rng::\n{\nSend foo\n}");

        result.Trigger.Should().Be("rng");
        result.Body.Should().Be("Send foo");
        result.UnexpressibleOptions.Should().BeEmpty();
    }

    [Fact]
    public void Decompose_InlineReplacement_ExtractsBody()
    {
        RawDecomposition result = RawDefinition.Decompose("::btw::by the way");

        result.Trigger.Should().Be("btw");
        result.Body.Should().Be("by the way");
    }

    [Fact]
    public void Decompose_SurfacesUnexpressibleOptions()
    {
        RawDecomposition result = RawDefinition.Decompose(":K1000 SE*:ftw::for the win");

        result.Trigger.Should().Be("ftw");
        // '*' is expressible via a checkbox; K1000 and SE are not.
        result.UnexpressibleOptions.Should().BeEquivalentTo("K1000", "SE");
    }

    [Fact]
    public void Decompose_CleanContinuationSection_ExtractsBodyWithoutLoss()
    {
        RawDecomposition result = RawDefinition.Decompose(":*:col::\n(\nred\ngreen\nblue\n)");

        result.Trigger.Should().Be("col");
        result.Body.Should().Be("red\ngreen\nblue");
        result.LossyReasons.Should().BeEmpty();
    }

    [Fact]
    public void Decompose_ContinuationWithOptions_IsLossy()
    {
        RawDecomposition result = RawDefinition.Decompose(":*:col::\n(Join`n RTrim0\nred\nblue\n)");

        result.Body.Should().Be("red\nblue");
        result.LossyReasons.Should().Contain(r => r.Contains("continuation options"));
    }

    [Fact]
    public void Decompose_ContinuationWithTrailingWhitespace_IsLossy()
    {
        RawDecomposition result = RawDefinition.Decompose(":*:col::\n(\nred   \nblue\n)");

        result.LossyReasons.Should().Contain("significant trailing whitespace");
    }
}
