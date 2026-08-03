using AHKFlowApp.Application.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class RawHotkeyBodyScannerTests
{
    // --- Rejected: a depth-0 line beyond line 0 opens a new definition --------------------

    [Fact]
    public void HotkeyDefinitionOnSecondLine_ReturnsThatLine()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n^a::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void HotstringDefinitionOnSecondLine_ReturnsThatLine()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n::btw::by the way");

        line.Should().Be(2);
    }

    [Fact]
    public void PrefixSymbols_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n$^!a::Send(\"x\")");

        line.Should().Be(2);
    }

    [Fact]
    public void CustomCombination_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\nNumpad0 & Numpad1::Send(\"x\")");

        line.Should().Be(2);
    }

    [Fact]
    public void KeyUp_OnNormalHotkey_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n^!r Up::MsgBox(\"x\")");

        line.Should().Be(2);
    }

    [Fact]
    public void KeyUp_OnCustomCombination_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\nF1 & e Up::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void PunctuationKeyAfterCombination_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n~AppsKey & <::Send(\"x\")");

        line.Should().Be(2);
    }

    [Fact]
    public void ColonAsKey_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n^:::Send(\"x\")");

        line.Should().Be(2);
    }

    // AHK v2 (KeyList.htm, "Keyboard"): "Although any single character can be used as a key name,
    // its meaning (scan code or virtual keycode) depends on the current keyboard layout." A key
    // name is therefore not limited to ASCII letters, digits and a short punctuation list.
    [Fact]
    public void NonAsciiSingleCharacterKey_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\né::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void SymbolKeyOutsideTheOldPunctuationList_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n@::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void NonAsciiKeyInACustomCombination_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\nF1 & é::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void IndentedDefinition_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\n\t^a::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void CrLf_LineNumberSurvivesNormalization()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\r\n^a::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void LoneCr_LineNumberSurvivesNormalization()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("return\r^a::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void TwoInjectedDefinitions_ReturnsTheFirst()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "return\n^a::Run(\"calc\")\n^b::Run(\"calc\")");

        line.Should().Be(2);
    }

    [Fact]
    public void DefinitionAfterClosedContinuationSection_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "Send(\"a\")\n(\ntext\n)\n^a::Run(\"calc\")");

        line.Should().Be(5);
    }

    // AHK v2 (Scripts.htm): "any code after the closing parenthesis is also joined with the other
    // lines". So a continuation section ends at the first line whose first non-blank character is
    // ")", even when real code follows it — the closing line is not required to be ")" alone.
    [Fact]
    public void DefinitionAfterAClosingParenthesisWithTrailingCode_StillDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "FileAppend \"\n(\nLine 1 of the text.\n)\", \"C:\\File.txt\"\n^a::Run(\"calc\")");

        line.Should().Be(5);
    }

    // AHK v2 (Scripts.htm): "to have a line start with literal closing parenthesis, precede it
    // with an accent/backtick: `)". An escaped one is literal text and must not end the section.
    [Fact]
    public void EscapedClosingParenthesis_DoesNotEndTheContinuationSection()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "Send(\"a\")\n(\n`)\n^a::Run(\"calc\")\n)");

        line.Should().BeNull();
    }

    // --- Mutation guards: each proves a specific rule is doing real work -------------------

    [Fact]
    public void DefinitionOnLineZero_IsNotACandidate()
    {
        // Line 0 belongs to the emitter's own left-hand side and can never be top-level.
        // Fails if the line-0 exclusion is removed.
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("^a::Run(\"calc\")");

        line.Should().BeNull();
    }

    [Fact]
    public void BracesInsideLineComments_DoNotHideAnInjectedDefinition()
    {
        // Naive brace counting reads line 1 depth as 1 ("{" in a comment), which would make
        // line 2 look nested and hide it. Fails if the scanner reuses naive brace counting.
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "return ; {\n^a::Run(\"calc\")\n; }");

        line.Should().Be(2);
    }

    [Fact]
    public void BraceInsideAString_DoesNotHideAnInjectedDefinition()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "Send(\"{\")\n^a::Run(\"calc\")");

        line.Should().Be(2);
    }

    // AHK v2 accepts single-quoted strings too (Language.htm: "enclosed... in single or double
    // quotation marks"). Fails if the scanner only tracks double quotes.
    [Fact]
    public void BraceInsideASingleQuotedString_DoesNotHideAnInjectedDefinition()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "MsgBox('{')\n^a::Run(\"calc\")\nMsgBox('}')");

        line.Should().Be(2);
    }

    [Fact]
    public void BlockCommentedDefinition_IsIgnored()
    {
        // Fails if block comments are not recognized.
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "return\n/*\n^a::Run(\"calc\")\n*/");

        line.Should().BeNull();
    }

    // AHK v2 (Language.htm): "*/" closes a block comment when it appears at the start OR the end
    // of a line — not only when the whole trimmed line is "*/". Fails if the closer is only
    // recognized as an exact-line match.
    [Fact]
    public void BlockCommentClosedByTrailingCloser_StillDetectsDefinitionAfter()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "return\n/*\ncomment */\n^a::Run(\"calc\")");

        line.Should().Be(4);
    }

    // AHK v2 (Language.htm): "Excluding tabs and spaces, /* must appear at the start of the line,
    // while */ can appear only at the start or end of a line." Fails if only the trailing closer
    // is recognized, which would leave every later line hidden inside the comment.
    [Fact]
    public void BlockCommentClosedByLeadingCloser_StillDetectsDefinitionAfter()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "return\n/*\ncomment\n*/ ; close\n^a::Run(\"calc\")");

        line.Should().Be(5);
    }

    [Fact]
    public void DefinitionOnTheSameLineAsALeadingCloser_IsDetected()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "return\n/*\ncomment\n*/ ^a::Run(\"calc\")");

        line.Should().Be(4);
    }

    // --- Accepted: definition-shaped text that is not a real top-level definition ----------

    [Fact]
    public void DefinitionLookingTextInsideBraces_IsAccepted()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "{\n    x := 1\n    MsgBox(\"a::b\")\n}");

        line.Should().BeNull();
    }

    [Fact]
    public void DepthZeroNonDefinitionShapedLine_IsAccepted()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("Send(\"a\")\nMsgBox(\"a::b\")");

        line.Should().BeNull();
    }

    [Fact]
    public void LineComment_IsIgnored()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine("Send(\"a\")\n; ^a::Run(\"calc\")");

        line.Should().BeNull();
    }

    [Fact]
    public void TrailingLineComment_IsIgnored()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "Send(\"a\")\nSend(\"x\") ; ^a::Run(\"calc\")");

        line.Should().BeNull();
    }

    [Fact]
    public void ContinuationSectionLiteralText_IsAccepted()
    {
        int? line = RawHotkeyBodyScanner.FindInjectedDefinitionLine(
            "Send(\"a\")\n(\n^a::Run(\"calc\")\n)");

        line.Should().BeNull();
    }

    [Fact]
    public void ShippedPastePlainTextBody_IsAccepted()
    {
        // src/Backend/AHKFlowApp.Application/Constants/DefaultHotkeyCatalog.cs:77-85
        const string body =
            "{\n" +
            "    saved := ClipboardAll()      ; preserve the original rich clipboard\n" +
            "    A_Clipboard := A_Clipboard   ; reading returns text-only, stripping formatting\n" +
            "    Send(\"^v\")\n" +
            "    Sleep(150)                   ; let the paste consume the clipboard first\n" +
            "    A_Clipboard := saved         ; restore the original formatting\n" +
            "    saved := \"\"\n" +
            "}";

        RawHotkeyBodyScanner.FindInjectedDefinitionLine(body).Should().BeNull();
    }
}
