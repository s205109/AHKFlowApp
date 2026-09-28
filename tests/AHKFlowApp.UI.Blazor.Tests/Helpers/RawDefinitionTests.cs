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

    // Backlog 161. One theory for the whole option-resolution table. The repeated-flag rows are
    // the ones that matter: a resolver that ignored every cancel token would still pass every row
    // where the cancel stands alone, because cancelling gives back the default it started from.
    [Theory]
    // No options, then each of the four on its own.
    [InlineData("::btw::x", true, false, false, false)]
    [InlineData(":*:btw::x", false, false, false, false)]
    [InlineData(":?:btw::x", true, true, false, false)]
    [InlineData(":C:btw::x", true, false, true, false)]
    [InlineData(":O:btw::x", true, false, false, true)]
    // The pair from the bug report.
    [InlineData(":*C:btw::x", false, false, true, false)]
    // Repeated flags: the last one decides, in both directions.
    [InlineData(":**0:btw::x", true, false, false, false)]
    [InlineData(":*0*:btw::x", false, false, false, false)]
    [InlineData(":??0:btw::x", true, false, false, false)]
    [InlineData(":?0?:btw::x", true, true, false, false)]
    [InlineData(":CC0:btw::x", true, false, false, false)]
    [InlineData(":C0C:btw::x", true, false, true, false)]
    [InlineData(":OO0:btw::x", true, false, false, false)]
    [InlineData(":O0O:btw::x", true, false, false, true)]
    // C1 takes part in the same ordering as C and C0.
    [InlineData(":CC1:btw::x", true, false, false, false)]
    [InlineData(":C1C:btw::x", true, false, true, false)]
    // 'O' survives alongside '*'; the gate lives in the two write paths, not here.
    [InlineData(":*O:btw::x", false, false, false, true)]
    // AutoHotkey reads option letters without regard to case.
    [InlineData(":c?:btw::x", true, true, true, false)]
    // Every cancel token at once, which must land exactly on the defaults.
    [InlineData(":*0?0C0O0:btw::x", true, false, false, false)]
    public void Decompose_ResolvesTheFourStructuredOptions(
        string definition, bool endingRequired, bool insideWord, bool caseSensitive, bool omitEnding)
    {
        RawDecomposition result = RawDefinition.Decompose(definition);

        result.Options.Should().Be(
            new RawTriggerOptions(endingRequired, insideWord, caseSensitive, omitEnding));
    }

    // Decompose gives up on four separate paths before it reads an option block. Each one must
    // still report the AutoHotkey defaults, because the caller assigns whatever comes back.
    [Theory]
    [InlineData("")]                      // nothing but blank lines
    [InlineData("not a definition")]      // no leading ':'
    [InlineData(":onlyonecolon")]         // no second ':'
    [InlineData(":opts:trigger")]         // no '::' after the trigger
    public void Decompose_UnreadableDefinition_ReportsTheDefaults(string definition)
    {
        RawDecomposition result = RawDefinition.Decompose(definition);

        result.Options.Should().Be(new RawTriggerOptions(true, false, false, false));
    }

    [Fact]
    public void Decompose_CancelTokens_AreExpressible()
    {
        // A structured field holds each resolved value, so none of these is discarded by a switch
        // away from Raw, and warning that they are would be false.
        RawDecomposition result = RawDefinition.Decompose(":*0?0C0O0:btw::x");

        result.UnexpressibleOptions.Should().BeEmpty();
    }

    [Fact]
    public void Decompose_C1_KeepsWarning()
    {
        // C1 also stops case conforming, and no structured field holds that half of it.
        RawDecomposition result = RawDefinition.Decompose(":C1:btw::x");

        result.UnexpressibleOptions.Should().BeEquivalentTo("C1");
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

    [Fact]
    public void Decompose_LeadingComment_LiftedAndDefinitionParsed()
    {
        RawDecomposition result = RawDefinition.Decompose("; my note\n::btw::by the way");

        result.Trigger.Should().Be("btw");
        result.Body.Should().Be("by the way");
        result.LiftedComment.Should().Be("my note");
    }

    [Fact]
    public void Decompose_OtbBraceWithBody_ExcludesClosingBrace()
    {
        RawDecomposition result = RawDefinition.Decompose(":X:run::{\nRun \"notepad\"\n}");

        result.Trigger.Should().Be("run");
        result.Body.Should().Be("Run \"notepad\"");
    }

    [Fact]
    public void Decompose_TextModeLiteralBrace_IsInlineReplacement()
    {
        RawDecomposition result = RawDefinition.Decompose(":T:x::{");

        result.Trigger.Should().Be("x");
        result.Body.Should().Be("{");
    }
}
