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

    // --- OTB braces (option-sensitive) ---------------------------------------------------

    [Fact]
    public void Otb_BraceOnDefinitionLine_Accepted()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":X:run::{\nRun \"notepad.exe\"\n}");

        r.IsValid.Should().BeTrue();
        r.BodyKind.Should().Be(RawBodyKind.Braces);
        r.Trigger.Should().Be("run");
    }

    [Fact]
    public void Otb_NoOptions_Accepted()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::btw::{\nSend foo\n}");

        r.IsValid.Should().BeTrue();
        r.BodyKind.Should().Be(RawBodyKind.Braces);
    }

    [Theory]
    [InlineData(":T:brace::{")]   // text mode: "{" is an inline literal replacement
    [InlineData(":R:brace::{")]   // raw mode: same
    [InlineData(":T0T:brace::{")] // last T wins → mode active → inline literal
    [InlineData(":T0R:brace::{")]
    public void Otb_TextOrRawModeActive_IsInlineLiteral_NotOtb(string input)
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(input);

        r.IsValid.Should().BeTrue();
        r.BodyKind.Should().Be(RawBodyKind.Inline);
    }

    [Theory]
    [InlineData(":*:x::{\n}")]     // no send-mode → OTB
    [InlineData(":T0:x::{\n}")]    // T0 cancels text mode → OTB
    [InlineData(":R0:x::{\n}")]    // R0 cancels raw mode → OTB
    [InlineData(":TT0:x::{\n}")]   // last T0 wins → mode off → OTB
    [InlineData(":RT0:x::{\n}")]
    public void Otb_ModeOff_IsBraceBody(string input)
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(input);

        r.IsValid.Should().BeTrue();
        r.BodyKind.Should().Be(RawBodyKind.Braces);
    }

    [Fact]
    public void Normalize_Otb_RewritesBraceToOwnLine()
    {
        string normalized = RawHotstringDefinitionParser.Normalize(":X:run::{\nRun \"notepad.exe\"\n}");

        normalized.Should().Be(":X:run::\n{\nRun \"notepad.exe\"\n}");
    }

    [Fact]
    public void Normalize_ContinuationBody_PreservesTrailingWhitespaceByteForByte()
    {
        // Trailing spaces/tabs inside ( … ) are significant under RTrim0 and must survive; the
        // def/opener/closer lines outside the body are still trimmed.
        string input = ":*:col::   \n(\nred   \n\tblue\t\n)";

        string normalized = RawHotstringDefinitionParser.Normalize(input);

        normalized.Should().Be(":*:col::\n(\nred   \n\tblue\t\n)");
    }

    // --- Continuation sections -----------------------------------------------------------

    [Fact]
    public void ContinuationSection_HappyPath_IsValid()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:long::\n(\nline1\nline2\n)");

        r.IsValid.Should().BeTrue();
        r.Trigger.Should().Be("long");
        r.BodyKind.Should().Be(RawBodyKind.Continuation);
        r.BodyLineCount.Should().Be(2);
        r.DefinitionCount.Should().Be(1);
        r.Error.Should().BeNull();
    }

    [Theory]
    [InlineData(":*:x::\n(Join`n\nline1\nline2\n)")]
    [InlineData(":*:x::\n(LTrim\nline1\nline2\n)")]
    public void ContinuationSection_OpenerOptions_ArePassThrough(string input)
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(input);

        r.IsValid.Should().BeTrue();
        r.BodyKind.Should().Be(RawBodyKind.Continuation);
    }

    [Fact]
    public void ContinuationSection_OpenerWithParen_Rejected()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(Join)\nline1\n)");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("A continuation section opener must not contain `)` — put the closing `)` on its own line.");
    }

    [Fact]
    public void ContinuationSection_Unclosed_Rejected()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(\nline1\nline2");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Raw definition has an unclosed continuation section — add a closing `)` on its own line.");
    }

    [Fact]
    public void ContinuationSection_ContentAfterClose_Rejected()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(\nline1\n)\ntrailing");

        r.IsValid.Should().BeFalse();
        r.Error.Should().Be("Raw definition has content after the closing `)`.");
    }

    [Fact]
    public void ContinuationSection_InteriorBlankLines_Preserved()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(\nline1\n\nline3\n)");

        r.IsValid.Should().BeTrue();
        r.BodyLineCount.Should().Be(3);
    }

    [Fact]
    public void ContinuationSection_LiteralDefinitionLine_NotCountedAsDefinition()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(\n::example::text\nmore\n)");

        r.IsValid.Should().BeTrue();
        r.DefinitionCount.Should().Be(1);
    }

    [Fact]
    public void ContinuationSection_LiteralDirectiveLine_NotADirective()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(\n# Heading\nbody\n)");

        r.IsValid.Should().BeTrue();
        r.HasDirectiveOutsideLiteralBody.Should().BeFalse();
    }

    [Theory]
    [InlineData(":*:x::\n{\n#HotIf WinActive(\"X\")\nSend foo\n}")]
    [InlineData(":*:x::\n{\n#Requires AutoHotkey v2.0\n}")]
    public void BraceBody_DirectiveInside_StillFlagged(string input)
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(input);

        r.HasDirectiveOutsideLiteralBody.Should().BeTrue();
    }

    // --- BodyKind / BodyLineCount classification -----------------------------------------

    [Fact]
    public void BodyKind_Inline()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse("::btw::by the way");

        r.BodyKind.Should().Be(RawBodyKind.Inline);
        r.BodyLineCount.Should().Be(0);
    }

    [Fact]
    public void BodyKind_Braces()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::\n{\nSend foo\n}");

        r.BodyKind.Should().Be(RawBodyKind.Braces);
        r.BodyLineCount.Should().Be(0);
    }

    [Fact]
    public void BodyKind_Continuation()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:x::\n(\nline1\nline2\nline3\n)");

        r.BodyKind.Should().Be(RawBodyKind.Continuation);
        r.BodyLineCount.Should().Be(3);
    }

    [Fact]
    public void BodyKind_None_WhenNoBody()
    {
        RawParseResult r = RawHotstringDefinitionParser.Parse(":*:rng::");

        r.BodyKind.Should().Be(RawBodyKind.None);
        r.BodyLineCount.Should().Be(0);
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

    // --- Comment lifting (Prepare) -------------------------------------------------------

    [Fact]
    public void Prepare_LeadingComment_LiftedAndStripped()
    {
        RawPrepared p = RawHotstringDefinitionParser.Prepare("; my note\n::btw::by the way");

        p.LiftedComment.Should().Be("my note");
        p.NormalizedDefinition.Should().Be("::btw::by the way");
        p.Parsed.LiftedComment.Should().Be("my note");
        p.Parsed.IsValid.Should().BeTrue();
    }

    [Fact]
    public void Prepare_MultipleLeadingComments_JoinedWithNewline()
    {
        RawPrepared p = RawHotstringDefinitionParser.Prepare("; line one\n;line two\n::btw::x");

        p.LiftedComment.Should().Be("line one\nline two");
        p.NormalizedDefinition.Should().Be("::btw::x");
    }

    [Fact]
    public void Prepare_NoComment_PassesThrough()
    {
        RawPrepared p = RawHotstringDefinitionParser.Prepare("::btw::by the way");

        p.LiftedComment.Should().BeNull();
        p.NormalizedDefinition.Should().Be("::btw::by the way");
    }

    [Fact]
    public void Prepare_CommentInsideContinuationBody_NotLifted()
    {
        RawPrepared p = RawHotstringDefinitionParser.Prepare(":*:x::\n(\n; not a comment, literal text\nbody\n)");

        p.LiftedComment.Should().BeNull();
        p.NormalizedDefinition.Should().Be(":*:x::\n(\n; not a comment, literal text\nbody\n)");
    }

    [Fact]
    public void Prepare_CommentInsideBraceBody_NotLifted()
    {
        RawPrepared p = RawHotstringDefinitionParser.Prepare(":*:x::\n{\n; inside code\nSend foo\n}");

        p.LiftedComment.Should().BeNull();
        p.NormalizedDefinition.Should().Be(":*:x::\n{\n; inside code\nSend foo\n}");
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
