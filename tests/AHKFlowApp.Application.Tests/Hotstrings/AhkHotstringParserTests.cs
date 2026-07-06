using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Hotstrings;

[Trait("Category", "Unit")]
public sealed class AhkHotstringParserTests
{
    [Fact]
    public void Parse_PlainHotstring_ReturnsReadyWithDomainDefaults()
    {
        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse("::btw::by the way");

        rows.Should().ContainSingle();
        HotstringImportRowDto row = rows[0];
        row.Trigger.Should().Be("btw");
        row.Replacement.Should().Be("by the way");
        row.IsEndingCharacterRequired.Should().BeTrue();
        row.IsTriggerInsideWord.Should().BeFalse();
        row.IgnoredFlags.Should().BeEmpty();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
        row.LineNumber.Should().Be(1);
    }

    [Fact]
    public void Parse_StarFlag_DropsEndingCharacterRequirement()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":*:btw::by the way")[0];

        row.IsEndingCharacterRequired.Should().BeFalse();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_QuestionFlag_EnablesTriggerInsideWord()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":?:btw::by the way")[0];

        row.IsTriggerInsideWord.Should().BeTrue();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_StarQuestionFlags_SetBothWithoutWarning()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":*?:btw::by the way")[0];

        row.IsEndingCharacterRequired.Should().BeFalse();
        row.IsTriggerInsideWord.Should().BeTrue();
        row.IgnoredFlags.Should().BeEmpty();
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_UnknownFlag_IsWarningWithIgnoredFlag()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":C:btw::by the way")[0];

        row.IgnoredFlags.Should().Contain("C");
        row.Status.Should().Be(HotstringImportRowStatus.Warning);
    }

    [Theory]
    [InlineData(":B0:btw::x", "B0")]
    [InlineData(":K5:btw::x", "K5")]
    [InlineData(":SI:btw::x", "SI")]
    public void Parse_ParameterizedOrMultiLetterFlag_PreservedAsExactToken(string line, string expectedToken)
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(line)[0];

        row.IgnoredFlags.Should().ContainSingle().Which.Should().Be(expectedToken);
        row.Status.Should().Be(HotstringImportRowStatus.Warning);
    }

    [Fact]
    public void Parse_NonHotstringLines_AreIgnored()
    {
        string script = string.Join('\n',
            "; a comment",
            "",
            "#Requires AutoHotkey v2.0",
            "^!k::Send(\"x\")",
            "MsgBox(\"hello\")");

        AhkHotstringParser.Parse(script).Should().BeEmpty();
    }

    [Fact]
    public void Parse_TriggerTooLong_IsInvalid()
    {
        string longTrigger = new('a', 51);

        HotstringImportRowDto row = AhkHotstringParser.Parse($"::{longTrigger}::x")[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Contain("50");
    }

    [Fact]
    public void Parse_EmptyReplacement_IsInvalid()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::btw::")[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Contain("Replacement");
    }

    [Fact]
    public void Parse_TabInTrigger_IsInvalid()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::b\tw::x")[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Contain("tabs");
    }

    [Fact]
    public void Parse_MultiLineContinuation_ConvertsToMultiLineReplacement()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "line one",
            "line two",
            ")",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Trigger.Should().Be("sig");
        rows[0].Replacement.Should().Be("line one\nline two");
        rows[0].Status.Should().Be(HotstringImportRowStatus.Ready);
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_IndentedContinuationLines_TrimLeadingWhitespacePerLine()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "    indented one",
            "\tindented two",
            ")");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("indented one\nindented two");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_ContinuationLines_AreNotEscapeDecoded()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "literal `n stays",
            ")");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("literal `n stays");
    }

    [Fact]
    public void Parse_UnterminatedContinuation_IsInvalid()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "line one");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Unterminated continuation section.");
    }

    [Fact]
    public void Parse_CodeBodyWithoutReturnBeforeNextHotstring_IsInvalidAndNextRowParses()
    {
        string script = string.Join('\n',
            "::bad::",
            "Send hello",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Unterminated code body (no `return` before next hotstring).");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_CodeBodyWithoutReturnAtEof_IsInvalid()
    {
        string script = string.Join('\n',
            "::bad::",
            "MsgBox hi");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Unterminated code body (no `return`).");
    }

    [Fact]
    public void Parse_TerminatedLogicBody_IsInvalidWithHonestReason()
    {
        string script = string.Join('\n',
            "::d::",
            "FormatTime, X,, yyyy",
            "return",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_CodeBodyBlankAndCommentLines_AreSkippedNotTerminators()
    {
        string script = string.Join('\n',
            "::bad::",
            "MsgBox hi",
            "",
            "; a comment",
            "return");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
    }

    [Fact]
    public void Parse_CommentLineBetweenTriggerAndBody_IsStillTreatedAsCodeBody()
    {
        string script = string.Join('\n',
            "::note::",
            "; a leading comment before the real body",
            "MsgBox hi",
            "return");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().NotBe("Replacement is required.");
    }

    [Fact]
    public void Parse_EmptyHotstringWithOnlyTrailingComment_IsReplacementRequiredNotUnterminated()
    {
        string script = string.Join('\n',
            "::x::",
            "; just a trailing comment, no real body here",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Reason.Should().Be("Replacement is required.");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_NestedContinuationBlockInBody_IgnoresReturnAndHotstringLines()
    {
        string script = string.Join('\n',
            "::bad::",
            "x := 1",
            "(",
            "return",
            "::fake::not a new row",
            ")",
            "return",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
        rows[1].Trigger.Should().Be("btw");
    }

    [Fact]
    public void Parse_EmptyHotstringFollowedByHotstring_IsReplacementRequired()
    {
        string script = string.Join('\n',
            "::x::",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Reason.Should().Be("Replacement is required.");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_LoneTrailingBacktickReplacement_IsReplacementRequiredNotCodeBody()
    {
        // Regression guard: routing must key off the RAW (pre-decode) replacement text.
        // A raw single backtick decodes to "", but deciding on the DECODED value would
        // misroute this row into the code-body scanner, silently consuming the lines below.
        string script = string.Join('\n',
            "::x::`",
            "MsgBox hi",
            "return");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().ContainSingle();
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Be("Replacement is required.");
    }

    [Fact]
    public void Parse_LoneCarriageReturnLineEndings_AreNormalizedToSeparateLines()
    {
        string script = "::a::x\r::b::y";

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Trigger.Should().Be("a");
        rows[0].Replacement.Should().Be("x");
        rows[1].Trigger.Should().Be("b");
        rows[1].Replacement.Should().Be("y");
    }

    [Fact]
    public void Parse_IndentedHotstringLine_IsRecognizedAtTopLevel()
    {
        string script = "\t::btw::by the way";

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Trigger.Should().Be("btw");
        row.Replacement.Should().Be("by the way");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_IndentedHotstringLine_TerminatesCodeBodyAsHardBoundary()
    {
        string script = string.Join('\n',
            "::bad::",
            "MsgBox hi",
            "\t::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Reason.Should().Be("Unterminated code body (no `return` before next hotstring).");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_ContinuationClosedByLineWithTrailingComment_Terminates()
    {
        string script = string.Join('\n',
            "::sig::",
            "(",
            "line one",
            ") ; end of sig",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Trigger.Should().Be("sig");
        rows[0].Replacement.Should().Be("line one");
        rows[0].Status.Should().Be(HotstringImportRowStatus.Ready);
        rows[1].Trigger.Should().Be("btw");
    }

    [Fact]
    public void Parse_NestedBlockOpenedWithContinuationOptions_IgnoresInnerReturnAndHotstringLines()
    {
        string script = string.Join('\n',
            "::bad::",
            "x := 1",
            "( LTrim",
            "return",
            "::fake::not a new row",
            ")",
            "return",
            "::btw::by the way");

        IReadOnlyList<HotstringImportRowDto> rows = AhkHotstringParser.Parse(script);

        rows.Should().HaveCount(2);
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("aren't supported");
        rows[1].Trigger.Should().Be("btw");
    }

    [Fact]
    public void Parse_MvgpSendBody_ConvertsToTwoLineReplacement()
    {
        string script = string.Join('\n',
            "::mvgp::",
            "send Met vriendelijke Groet,{Return}",
            "send Bart Segers",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("Met vriendelijke Groet,\nBart Segers");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DbgSendBody_ConvertsToLiteralText()
    {
        string script = string.Join('\n',
            "::dbg::",
            "send mocha --debug-brk",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("mocha --debug-brk");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DTimeBody_IsRejectedNamingFormatTime()
    {
        string script = string.Join('\n',
            "::d-time::",
            "FormatTime, CurrentDateTime,, dd/MM/yyyy HH:mm",
            "SendInput %CurrentDateTime%",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: FormatTime).");
    }

    [Fact]
    public void Parse_LiClipboardBody_IsRejectedNamingFirstConstruct()
    {
        string script = string.Join('\n',
            "::li::",
            "clipsaved := ClipboardAll",
            "clipboard := \"[li]\"",
            "Send ^v",
            "clipboard := clipsaved",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: clipsaved).");
    }

    [Fact]
    public void Parse_SendWithInlineComment_RejectsWholeBody()
    {
        string script = string.Join('\n',
            "::x::",
            "Send, hello ; note",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Inline comment in Send — not imported.");
    }

    [Fact]
    public void Parse_SendWithEscapedSemicolon_KeepsLiteralSemicolon()
    {
        string script = string.Join('\n',
            "::x::",
            "Send, a`;b",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("a;b");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendCommaArg_TrimsLeadingWhitespaceKeepsTrailing()
    {
        string script = string.Join('\n',
            "::x::",
            "Send,   hello world ",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("hello world ");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendWithPercentVariable_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "SendInput %CurrentDateTime%",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: % character).");
    }

    [Fact]
    public void Parse_SendWithLiteralPercentSign_IsAlsoRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "Send, 100% done",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: % character).");
    }

    [Fact]
    public void Parse_SendWithModifierKeystroke_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "Send ^v",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: modifier ^).");
    }

    [Fact]
    public void Parse_SendWithUnsupportedBraceToken_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "Send {F5}",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: {F5}).");
    }

    [Fact]
    public void Parse_SendEnterAndTabTokens_ConvertToNewlineAndTab()
    {
        string script = string.Join('\n',
            "::x::",
            "Send a{Enter}b{Tab}c",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("a\nb\tc");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendRawBody_KeepsBracesAndModifiersLiteral()
    {
        string script = string.Join('\n',
            "::x::",
            "SendRaw {Home}^+!",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("{Home}^+!");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_SendTextWithPercentVariable_IsRejected()
    {
        string script = string.Join('\n',
            "::x::",
            "SendText %x%",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Status.Should().Be(HotstringImportRowStatus.Invalid);
        row.Reason.Should().Be("Code-body hotstrings that run logic aren't supported (found: % character).");
    }

    [Fact]
    public void Parse_MultipleSends_ConcatenateWithNoSeparator()
    {
        string script = string.Join('\n',
            "::x::",
            "Send abc",
            "Send def",
            "return");

        HotstringImportRowDto row = AhkHotstringParser.Parse(script)[0];

        row.Replacement.Should().Be("abcdef");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Theory]
    [InlineData("::sig::line one`nline two", "line one\nline two")]
    [InlineData("::sig::a`rb", "a\rb")]
    [InlineData("::sig::a`tb", "a\tb")]
    [InlineData("::sig::back``tick", "back`tick")]
    [InlineData("::sig::a`sb", "a b")]
    [InlineData("::sig::a`;b", "a;b")]
    public void Parse_EscapedReplacement_DecodesEscapeSequences(string line, string expected)
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(line)[0];

        row.Replacement.Should().Be(expected);
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_DoubledBacktickBeforeN_KeepsLiteralBacktickAndN()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::keep ``n literal")[0];

        row.Replacement.Should().Be("keep `n literal");
    }

    [Fact]
    public void Parse_UnknownEscape_EmitsEscapedCharVerbatim()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::a`qb")[0];

        row.Replacement.Should().Be("aqb");
    }

    [Fact]
    public void Parse_TrailingLoneBacktick_IsDropped()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::abc`")[0];

        row.Replacement.Should().Be("abc");
    }

    [Fact]
    public void Parse_DoubleColonInsideReplacement_KeepsRemainderVerbatim()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse("::sig::a::b")[0];

        row.Trigger.Should().Be("sig");
        row.Replacement.Should().Be("a::b");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }

    [Fact]
    public void Parse_TriggerWithSurroundingWhitespace_IsTrimmed()
    {
        HotstringImportRowDto row = AhkHotstringParser.Parse(":: btw ::text")[0];

        row.Trigger.Should().Be("btw");
        row.Replacement.Should().Be("text");
        row.Status.Should().Be(HotstringImportRowStatus.Ready);
    }
}
