using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class MacroTokenParserTests
{
    // Cross-task contract (Task 3 validator surfaces this verbatim) — keep in sync with the
    // plan's example message (docs/superpowers/plans/2026-07-10-hotstrings-redesign-phase3.md).
    private const string Allowed = "Allowed: {{cursor}}, {{key:Enter}}, {{key:Tab}}.";

    private static MacroToken.TextRun Text(string s) => new(s);
    private static MacroToken.Key Key(string name) => new(name);
    private static MacroToken.Cursor Cursor() => new();

    private static string UnknownToken(string raw) => $"Unknown token '{raw}'. {Allowed}";

    [Fact]
    public void PlainText_NoTokens_SingleTextRun_NoErrors()
    {
        MacroParseResult result = MacroTokenParser.Parse("hello world");

        result.Tokens.Should().Equal(Text("hello world"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void CursorToken_ParsedAlone()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{cursor}}");

        result.Tokens.Should().Equal(Cursor());
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void KeyEnterToken_ParsedAlone()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{key:Enter}}");

        result.Tokens.Should().Equal(Key("Enter"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void KeyTabToken_ParsedAlone()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{key:Tab}}");

        result.Tokens.Should().Equal(Key("Tab"));
        result.Errors.Should().BeEmpty();
    }

    [Theory]
    [InlineData("{{CURSOR}}")]
    [InlineData("{{Cursor}}")]
    [InlineData("{{cUrSoR}}")]
    public void CursorToken_CaseInsensitive(string input)
    {
        MacroTokenParser.Parse(input).Tokens.Should().Equal(Cursor());
    }

    [Theory]
    [InlineData("{{Key:enter}}", "Enter")]
    [InlineData("{{KEY:ENTER}}", "Enter")]
    [InlineData("{{key:TAB}}", "Tab")]
    [InlineData("{{KEY:tab}}", "Tab")]
    public void KeyToken_CaseInsensitive_CanonicalName(string input, string expectedName)
    {
        MacroTokenParser.Parse(input).Tokens.Should().Equal(Key(expectedName));
    }

    [Fact]
    public void InteriorWhitespace_IsStrictError()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{ cursor }}");

        result.Errors.Should().Equal(UnknownToken("{{ cursor }}"));
        result.Tokens.Should().BeEmpty();
    }

    [Fact]
    public void UnknownTokenName_IsStrictError()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{oops}}");

        result.Errors.Should().Equal(UnknownToken("{{oops}}"));
    }

    [Fact]
    public void UnknownKeyName_IsStrictError()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{key:Escape}}");

        result.Errors.Should().Equal(UnknownToken("{{key:Escape}}"));
    }

    [Fact]
    public void UnknownFieldStyleToken_IsStrictError()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{field:name}}");

        result.Errors.Should().Equal(UnknownToken("{{field:name}}"));
    }

    [Fact]
    public void TokenCandidateSpanningNewline_IsStrictError()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{key:\nEnter}}");

        result.Errors.Should().Equal(UnknownToken("{{key:\nEnter}}"));
    }

    [Fact]
    public void UnmatchedOpenBraces_NoClosingPair_TreatedAsLiteralText()
    {
        MacroParseResult result = MacroTokenParser.Parse("a{{b no closer here");

        result.Tokens.Should().Equal(Text("a{{b no closer here"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void SingleUnpairedBraces_TreatedAsLiteralText()
    {
        MacroParseResult result = MacroTokenParser.Parse("a{b}c");

        result.Tokens.Should().Equal(Text("a{b}c"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void AdjacentTokens_NoTextBetween_NoEmptyTextRun()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{key:Enter}}{{key:Tab}}{{cursor}}");

        result.Tokens.Should().Equal(Key("Enter"), Key("Tab"), Cursor());
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void MultilineTextRun_PreservedVerbatim_WhenNoTokens()
    {
        string input = "Line1\nLine2\r\nLine3";

        MacroTokenParser.Parse(input).Tokens.Should().Equal(Text(input));
    }

    [Fact]
    public void TokenStream_PreservesOrdering_ForLaterCursorMath()
    {
        // The parser doesn't compute offsets itself (Task 2's job) — but the token stream's
        // order and TextRun contents must give a later consumer everything it needs to derive
        // "characters after cursor" by simple summation.
        MacroParseResult result = MacroTokenParser.Parse("abc{{cursor}}def");

        result.Tokens.Should().Equal(Text("abc"), Cursor(), Text("def"));
    }

    [Fact]
    public void EscapedLiteral_EmitsDoubledBraceText()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{{{first_name}}}}");

        result.Tokens.Should().Equal(Text("{{first_name}}"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void EscapedLiteral_AdjacentToRealTokens_Decision11Example()
    {
        MacroParseResult result = MacroTokenParser.Parse(
            "Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex");

        result.Tokens.Should().Equal(
            Text("Dear {{first_name}},"),
            Key("Enter"),
            Cursor(),
            Text("Alex"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void EscapedLiteral_AllowsWhitespaceAndNewlinesInsideInnerContent()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{{{ some \n mustache var }}}}");

        result.Tokens.Should().Equal(Text("{{ some \n mustache var }}"));
        result.Errors.Should().BeEmpty();
    }

    [Fact]
    public void UnclosedEscape_NoClosingQuadBrace_LeadingPairIsLiteral_InnerTokenStillScanned()
    {
        // "{{{{" with no "}}}}" anywhere ahead: only the leading "{{" is literal; scanning
        // resumes right after it, so the remaining "{{oops}}" is evaluated as a real token
        // candidate (and fails strictly, since it isn't a known token).
        MacroParseResult result = MacroTokenParser.Parse("{{{{oops}}");

        result.Tokens.Should().Equal(Text("{{"));
        result.Errors.Should().Equal(UnknownToken("{{oops}}"));
    }

    [Fact]
    public void UnclosedEscape_ContainingMalformedRealToken_StillSurfacesStrictError()
    {
        // Decision-11 edge case from the plan: unclosed escape wrapping a typo'd real token —
        // the leading "{{" is literal, and "{{key:Entr}}" still raises its own strict error.
        MacroParseResult result = MacroTokenParser.Parse("{{{{key:Entr}}");

        result.Tokens.Should().Equal(Text("{{"));
        result.Errors.Should().Equal(UnknownToken("{{key:Entr}}"));
    }

    [Fact]
    public void TypoKeyToken_StillErrors_EvenNextToAValidEscape()
    {
        MacroParseResult result = MacroTokenParser.Parse("{{{{first_name}}}}{{key:Entr}}");

        result.Tokens.Should().Equal(Text("{{first_name}}"));
        result.Errors.Should().Equal(UnknownToken("{{key:Entr}}"));
    }
}
