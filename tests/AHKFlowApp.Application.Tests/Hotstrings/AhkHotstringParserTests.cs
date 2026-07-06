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
    public void Parse_MultiLineContinuation_IsInvalidAndConsumesInnerLines()
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
        rows[0].Status.Should().Be(HotstringImportRowStatus.Invalid);
        rows[0].Reason.Should().Contain("Multi-line");
        rows[1].Trigger.Should().Be("btw");
        rows[1].Status.Should().Be(HotstringImportRowStatus.Ready);
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
