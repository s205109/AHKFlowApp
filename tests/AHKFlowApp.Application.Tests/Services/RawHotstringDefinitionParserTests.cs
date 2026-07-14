using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class RawHotstringDefinitionParserTests
{
    // --- Structure: first-line split -----------------------------------------------------

    [Fact]
    public void InlineDefinition_SplitsOptionsTriggerBody()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":K1000 SE*:ftw::for the win");

        r.FirstLineValid.Should().BeTrue();
        r.IsValid.Should().BeTrue();
        r.Trigger.Should().Be("ftw");
        r.OptionTokens.Should().Equal("K1000", "SE", "*");
        r.UnknownOptionTokens.Should().BeEmpty();
        r.DefinitionCount.Should().Be(1);
        r.Error.Should().BeNull();
    }

    [Fact]
    public void NoOptions_InlineDefinition_IsValid()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::btw::by the way");

        r.IsValid.Should().BeTrue();
        r.Trigger.Should().Be("btw");
        r.OptionTokens.Should().BeEmpty();
    }

    [Fact]
    public void NotAHotstring_FirstLineInvalid()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("just some text");

        r.FirstLineValid.Should().BeFalse();
        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Not a valid hotstring definition — expected `:options:trigger::replacement`.");
    }

    [Fact]
    public void LeadingBlankLines_Tolerated()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("\n\n::btw::by the way");

        r.IsValid.Should().BeTrue();
        r.Trigger.Should().Be("btw");
    }

    // --- Brace body ----------------------------------------------------------------------

    [Fact]
    public void BraceBody_BalancedIsValid()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::\n{\nSend String(Random(1, 100))\n}");

        r.IsValid.Should().BeTrue();
        r.Trigger.Should().Be("rng");
        r.Error.Should().BeNull();
    }

    [Fact]
    public void BraceBody_Unbalanced_ReportsBraceError()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::\n{\nSend foo\n");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Raw definition must have balanced braces.");
    }

    [Fact]
    public void BraceBody_ContentAfterClose_ReportsError()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::\n{\nSend foo\n}\ntrailing");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Raw definition has content after the closing brace.");
    }

    [Fact]
    public void BareTrigger_NoBody_RequiresBrace()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Put `{` on its own line below the trigger.");
    }

    [Fact]
    public void NestedBraces_Balanced_IsValid()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n{\nif (a) {\nb()\n}\n}");

        r.IsValid.Should().BeTrue();
    }

    // --- Inline replacement forms --------------------------------------------------------

    [Fact]
    public void InlineWithBrace_NotBraceBalanceChecked()
    {
        // Rule 6 does not apply to inline replacements: ":*:brace::{{}" is accepted.
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:brace::{{}");

        r.IsValid.Should().BeTrue();
        r.Trigger.Should().Be("brace");
    }

    [Fact]
    public void InlineReplacement_WithTrailingLines_Rejected()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::btw::by the way\nextra line");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Raw definition has content after the inline replacement.");
    }

    // --- OTB brace / continuation rejection ----------------------------------------------

    [Fact]
    public void OpeningBraceOnDefinitionLine_Rejected()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::btw:: {\nSend foo\n}");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Put `{` on its own line below the trigger.");
    }

    [Fact]
    public void ContinuationSection_Rejected()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:long::\n(\nline1\nline2\n)");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Put `{` on its own line below the trigger.");
    }

    // --- Multi-definition detection ------------------------------------------------------

    [Fact]
    public void TwoInlineDefinitions_CountIsTwo()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::a::1\n::b::2");

        r.DefinitionCount.Should().Be(2);
    }

    [Fact]
    public void SingleBraceBodyDefinition_CountIsOne()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::\n{\nSend foo\n}");

        r.DefinitionCount.Should().Be(1);
    }

    // --- Escaped-trigger decode ----------------------------------------------------------

    [Fact]
    public void EscapedSemicolonTrigger_Decoded()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::`;foo::bar");

        r.Trigger.Should().Be(";foo");
    }

    [Fact]
    public void EscapedNewlineTrigger_DecodesToLineBreak()
    {
        // Decodes to an actual newline; rule 3 (validator) rejects it, but the parser decodes faithfully.
        RawParseResult r = RawHotstringDefinitionParser.Parse("::a`nb::x");

        r.Trigger.Should().Be("a\nb");
    }

    [Theory]
    [InlineData(":*: foo::bar", " foo")]   // leading space
    [InlineData(":C:bar ::x", "bar ")]     // trailing space
    public void Trigger_PreservesLiteralWhitespace(string input, string expected)
    {
        // Spaces/tabs are literal within an AHK abbreviation and the raw text is emitted verbatim,
        // so the derived trigger must not be trimmed (else dedup/DB/UI disagree with the script).
        RawHotstringDefinitionParser.Parse(input).Trigger.Should().Be(expected);
    }

    // --- Option tokenization: longest-match & known set ----------------------------------

    [Theory]
    [InlineData(":SE*:t::x", new[] { "SE", "*" })]
    [InlineData(":S0:t::x", new[] { "S0" })]
    [InlineData(":SI:t::x", new[] { "SI" })]
    [InlineData(":SP:t::x", new[] { "SP" })]
    [InlineData(":K-1:t::x", new[] { "K-1" })]
    [InlineData(":P9:t::x", new[] { "P9" })]
    [InlineData(":C1 B0:t::x", new[] { "C1", "B0" })]
    public void OptionTokenization_LongestMatch(string input, string[] expected)
    {
        RawHotstringDefinitionParser.Parse(input).OptionTokens.Should().Equal(expected);
    }

    [Theory]
    [InlineData(":*:t::x")]
    [InlineData(":?0:t::x")]
    [InlineData(":c:t::x")]      // lowercase known flag
    [InlineData(":se*:t::x")]    // lowercase SE
    public void KnownOptions_ProduceNoUnknownTokens(string input)
    {
        RawHotstringDefinitionParser.Parse(input).UnknownOptionTokens.Should().BeEmpty();
    }

    [Fact]
    public void X0_IsRejectedAsUnknown()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":X0:t::x");

        r.OptionTokens.Should().Equal("X0");
        r.UnknownOptionTokens.Should().Equal("X0");
    }

    [Fact]
    public void UnknownFlag_Captured()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":Q:t::x");

        r.UnknownOptionTokens.Should().Equal("Q");
    }
}
