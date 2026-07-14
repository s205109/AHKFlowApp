using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Microsoft.Extensions.Time.Testing;
using NSubstitute;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkScriptGeneratorTests
{
    private static AhkScriptGenerator DefaultSut()
    {
        IAppVersionProvider version = Substitute.For<IAppVersionProvider>();
        version.GetVersion().Returns("0.0.0");
        return new AhkScriptGenerator(new HeaderTokenRenderer(), TimeProvider.System, version);
    }

    [Fact]
    public void Generate_EmptyProfile_EmitsHeaderSectionMarkersAndFooter()
    {
        Profile profile = new ProfileBuilder()
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("; end of file")
            .Build();

        string output = DefaultSut().Generate(profile, [], []);

        output.Should().Be(
            "#Requires AutoHotkey v2.0\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
            "; end of file");
    }

    [Fact]
    public void Generate_EmptyHeaderAndFooter_StillEmitsSectionMarkers()
    {
        Profile profile = new ProfileBuilder().WithHeader("").WithFooter("").Build();

        string output = DefaultSut().Generate(profile, [], []);

        output.Should().Be(
            "\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n");
    }

    [Theory]
    [InlineData(true, false, false, false, ":T:btw::by the way")]    // defaults — Text always emits T (WYSIWYG, D1)
    [InlineData(false, false, false, false, ":*T:btw::by the way")]  // expand immediately
    [InlineData(true, true, false, false, ":?T:btw::by the way")]    // trigger inside word
    [InlineData(true, false, true, false, ":CT:btw::by the way")]    // case sensitive
    [InlineData(true, false, false, true, ":OT:btw::by the way")]    // omit ending character
    [InlineData(false, false, false, true, ":*T:btw::by the way")]   // O suppressed when *
    [InlineData(false, true, true, true, ":*?CT:btw::by the way")]   // deterministic order * ? C O T
    public void Generate_Hotstring_FormatsOptionsCorrectly(
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        bool isCaseSensitive,
        bool omitEndingCharacter,
        string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(isEndingCharacterRequired)
            .WithTriggerInsideWord(isTriggerInsideWord)
            .WithCaseSensitive(isCaseSensitive)
            .WithOmitEndingCharacter(omitEndingCharacter)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Theory]
    [InlineData("line one\nline two", ":T:sig::line one`nline two")]
    [InlineData("a\rb", ":T:sig::a`rb")]
    [InlineData("a\tb", ":T:sig::a`tb")]
    [InlineData("a\r\nb", ":T:sig::a`r`nb")]
    [InlineData("back`tick", ":T:sig::back``tick")]
    [InlineData("literal `n stays\n", ":T:sig::literal ``n stays`n")]
    [InlineData("a ; b", ":T:sig::a `; b")]
    public void Generate_HotstringWithSpecialChars_EscapesOntoSinglePhysicalLine(
        string replacement, string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement(replacement)
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Theory]
    [InlineData("a ;b", ":T:a `;b::x")]
    [InlineData("back`tick", ":T:back``tick::x")]
    public void Generate_TriggerWithSpecialChars_EscapesTriggerToo(string trigger, string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger(trigger)
            .WithReplacement("x")
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_ClipboardDelivery_DefaultEndingCharacter_EmitsExecuteCallWithEndChar()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement("Kind regards,\nBart")
            .WithDelivery(HotstringDelivery.ClipboardPaste)
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":X:sig::AhkFlow_PasteReplacement(\"Kind regards,`nBart\", A_EndChar)");
    }

    [Theory]
    [InlineData(true, false, false, ":X:sig::AhkFlow_PasteReplacement(\"text\")")]
    [InlineData(false, false, false, ":X*:sig::AhkFlow_PasteReplacement(\"text\")")]
    [InlineData(false, true, true, ":X*?C:sig::AhkFlow_PasteReplacement(\"text\")")]
    public void Generate_ClipboardDelivery_OmitOrWildcard_OmitsEndCharAndKeepsOptionOrder(
        bool endingRequired,
        bool triggerInsideWord,
        bool caseSensitive,
        string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement("text")
            .WithDelivery(HotstringDelivery.ClipboardPaste)
            .WithEndingCharacterRequired(endingRequired)
            .WithTriggerInsideWord(triggerInsideWord)
            .WithCaseSensitive(caseSensitive)
            .WithOmitEndingCharacter(endingRequired)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(expectedLine);
        expectedLine.Split("::", StringSplitOptions.None)[0].Should().NotContain("T");
        expectedLine.Split("::", StringSplitOptions.None)[0].Should().NotContain("O");
    }

    [Fact]
    public void Generate_ClipboardDelivery_EscapesAhkStringLiteral()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("sig")
            .WithReplacement("quote \" back`tick\nline\tend")
            .WithDelivery(HotstringDelivery.ClipboardPaste)
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":X*:sig::AhkFlow_PasteReplacement(\"quote `\" back``tick`nline`tend\")");
    }

    [Fact]
    public void Generate_AutoDelivery_UsesTypedAt199AndClipboardAt200()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring typed = new HotstringBuilder()
            .WithTrigger("a199")
            .WithReplacement(new string('a', 199))
            .WithDelivery(HotstringDelivery.Auto)
            .WithTriggerInsideWord(false)
            .Build();
        Hotstring clipboard = new HotstringBuilder()
            .WithTrigger("b200")
            .WithReplacement(new string('b', 200))
            .WithDelivery(HotstringDelivery.Auto)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [typed, clipboard], []);

        output.Should().Contain($":T:a199::{new string('a', 199)}");
        output.Should().Contain(
            $":X:b200::AhkFlow_PasteReplacement(\"{new string('b', 200)}\", A_EndChar)");
    }

    [Fact]
    public void Generate_NonTextWithClipboardIntent_RemainsNonClipboard()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring macro = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{cursor}}")
            .WithDelivery(HotstringDelivery.ClipboardPaste)
            .Build();

        string output = DefaultSut().Generate(profile, [macro], []);

        output.Should().NotContain("AhkFlow_PasteReplacement");
        output.Should().Contain(":?:m::");
    }

    [Fact]
    public void Generate_ClipboardDelivery_EmitsHelperExactlyOnceAcrossContextGroups()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring global = new HotstringBuilder()
            .WithTrigger("global")
            .WithReplacement(new string('g', 200))
            .WithTriggerInsideWord(false)
            .Build();
        Hotstring contextual = new HotstringBuilder()
            .WithTrigger("context")
            .WithReplacement(new string('c', 200))
            .WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        string output = DefaultSut().Generate(profile, [global, contextual], []);

        output.Split("AhkFlow_PasteReplacement(text", StringSplitOptions.None)
            .Should().HaveCount(2);
        output.Should().StartWith("H\nAhkFlow_PasteReplacement(text");
    }

    [Fact]
    public void Generate_NoClipboardDelivery_OmitsHelper()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring typed = new HotstringBuilder()
            .WithTrigger("short")
            .WithReplacement("short text")
            .Build();

        string output = DefaultSut().Generate(profile, [typed], []);

        output.Should().NotContain("AhkFlow_PasteReplacement");
    }

    // Captured BEFORE any Phase-4 window-context changes to AhkScriptGenerator/HotstringEmitter —
    // this is the regression baseline proving no-context output is byte-identical pre/post change.
    [Fact]
    public void Generate_NoContextHotstrings_OutputByteIdenticalToFlatEmission()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs1 = new HotstringBuilder().WithTrigger("b").WithReplacement("beta")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring hs2 = new HotstringBuilder().WithTrigger("a").WithReplacement("alpha")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("n")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("hi")
            .Build();

        string output = DefaultSut().Generate(profile, [hs1, hs2], [hk]);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            ":T:a::alpha\n" +
            ":T:b::beta\n" +
            "; --- Hotkeys ---\n" +
            "; d\n" +
            "n::Send(\"hi\")\n" +
            "F");
    }

    [Fact]
    public void Generate_HotstringWithDescription_EmitsCommentAbove()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder().WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithDescription("a friendly note").Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "; a friendly note\n" +
            ":T:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_HotstringWithMultilineDescription_EmitsOneCommentPerLine()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder().WithTrigger("btw").WithReplacement("by the way")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithDescription("line one\nline two").Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "; line one\n" +
            "; line two\n" +
            ":T:btw::by the way\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_MultipleHotstrings_AllAppearUnderHotstringsSection()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs1 = new HotstringBuilder().WithTrigger("a").WithReplacement("alpha")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring hs2 = new HotstringBuilder().WithTrigger("b").WithReplacement("beta")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = DefaultSut().Generate(profile, [hs1, hs2], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            ":T:a::alpha\n" +
            ":T:b::beta\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Theory]
    [InlineData(false, false, false, false, "n")]               // no modifiers
    [InlineData(true, false, false, false, "^n")]               // Ctrl
    [InlineData(false, true, false, false, "!n")]               // Alt
    [InlineData(false, false, true, false, "+n")]               // Shift
    [InlineData(false, false, false, true, "#n")]               // Win
    [InlineData(true, true, false, false, "^!n")]               // Ctrl+Alt
    [InlineData(true, true, true, true, "^!+#n")]               // all four, prefix-order locked
    public void Generate_Hotkey_FormatsModifierPrefixesCorrectly(
        bool ctrl, bool alt, bool shift, bool win, string expectedLhs)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("n")
            .WithCtrl(ctrl).WithAlt(alt).WithShift(shift).WithWin(win)
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("hi")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
            "; d\n" +
            $"{expectedLhs}::Send(\"hi\")\n" +
            "F");
    }

    [Theory]
    [InlineData(AHKFlowApp.Domain.Enums.HotkeyAction.Send, "Send")]
    [InlineData(AHKFlowApp.Domain.Enums.HotkeyAction.Run, "Run")]
    public void Generate_Hotkey_EmitsCorrectActionFunctionName(
        AHKFlowApp.Domain.Enums.HotkeyAction action, string expectedFn)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("F5")
            .WithCtrl(false).WithAlt(false).WithShift(false).WithWin(false)
            .WithAction(action)
            .WithParameters("notepad.exe")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Contain($"F5::{expectedFn}(\"notepad.exe\")");
    }

    [Fact]
    public void Generate_Hotkey_EmitsParametersVerbatim_NoEscaping()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("a")
            .WithCtrl(true)
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("he said \"hi\"")
            .Build();

        string output = DefaultSut().Generate(profile, [], [hk]);

        output.Should().Contain("^a::Send(\"he said \"hi\"\")");
    }

    [Fact]
    public void Generate_Hotstrings_AreSortedByTriggerOrdinalAscending()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring c = new HotstringBuilder().WithTrigger("c").WithReplacement("c-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring a = new HotstringBuilder().WithTrigger("a").WithReplacement("a-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring b = new HotstringBuilder().WithTrigger("b").WithReplacement("b-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = DefaultSut().Generate(profile, [c, a, b], []);

        int posA = output.IndexOf(":T:a::a-rep", StringComparison.Ordinal);
        int posB = output.IndexOf(":T:b::b-rep", StringComparison.Ordinal);
        int posC = output.IndexOf(":T:c::c-rep", StringComparison.Ordinal);
        posA.Should().BeLessThan(posB);
        posB.Should().BeLessThan(posC);
    }

    [Fact]
    public void Generate_Hotkeys_AreSortedByDescriptionOrdinalAscending()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotkey z = new HotkeyBuilder().WithDescription("Zeta").WithKey("z")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("z").Build();
        Hotkey a = new HotkeyBuilder().WithDescription("Alpha").WithKey("a")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("a").Build();
        Hotkey m = new HotkeyBuilder().WithDescription("Mike").WithKey("m")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send).WithParameters("m").Build();

        string output = DefaultSut().Generate(profile, [], [z, a, m]);

        int posA = output.IndexOf("a::Send(\"a\")", StringComparison.Ordinal);
        int posM = output.IndexOf("m::Send(\"m\")", StringComparison.Ordinal);
        int posZ = output.IndexOf("z::Send(\"z\")", StringComparison.Ordinal);
        posA.Should().BeLessThan(posM);
        posM.Should().BeLessThan(posZ);
    }

    [Fact]
    public void Generate_Ordering_IsCultureIndependent_OrdinalNotInvariant()
    {
        // Ordinal sort: uppercase letters precede lowercase. Lock this in so future
        // refactors don't silently swap to InvariantCultureIgnoreCase.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring lower = new HotstringBuilder().WithTrigger("aa").WithReplacement("lower")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring upper = new HotstringBuilder().WithTrigger("AA").WithReplacement("upper")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();

        string output = DefaultSut().Generate(profile, [lower, upper], []);

        int posUpper = output.IndexOf(":T:AA::upper", StringComparison.Ordinal);
        int posLower = output.IndexOf(":T:aa::lower", StringComparison.Ordinal);
        posUpper.Should().BeLessThan(posLower);  // 'A' (0x41) < 'a' (0x61) in Ordinal
    }

    [Theory]
    [InlineData(true, false, false, false, ":X:dd::")]     // defaults
    [InlineData(false, false, false, false, ":X*:dd::")]   // expand immediately
    [InlineData(true, true, false, false, ":X?:dd::")]     // trigger inside word
    [InlineData(true, false, true, false, ":XC:dd::")]     // case sensitive
    [InlineData(true, false, false, true, ":XO:dd::")]     // omit ending character
    [InlineData(false, false, false, true, ":X*:dd::")]    // O suppressed when *
    [InlineData(false, true, true, true, ":X*?C:dd::")]    // deterministic order X * ? C O
    public void Generate_DateTimeHotstring_FormatsOptionsCorrectly_XPrefix(
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        bool isCaseSensitive,
        bool omitEndingCharacter,
        string expectedPrefix)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("dd")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy-MM-dd")
            .WithEndingCharacterRequired(isEndingCharacterRequired)
            .WithTriggerInsideWord(isTriggerInsideWord)
            .WithCaseSensitive(isCaseSensitive)
            .WithOmitEndingCharacter(omitEndingCharacter)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(expectedPrefix + "SendText(FormatTime(A_Now, \"yyyy-MM-dd\"))");
    }

    [Fact]
    public void Generate_DateTimeHotstring_NoOffset_MatchesSpecExample3()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("dd")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy-MM-dd")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(":X*:dd::SendText(FormatTime(A_Now, \"yyyy-MM-dd\"))");
    }

    [Fact]
    public void Generate_DateTimeHotstring_WithOffset_MatchesSpecExample4()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("nextweek")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("dddd d MMMM yyyy")
            .WithDateOffset(7, DateOffsetUnit.Days)
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":X*:nextweek::SendText(FormatTime(DateAdd(A_Now, 7, \"Days\"), \"dddd d MMMM yyyy\"))");
    }

    [Theory]
    [InlineData(DateOffsetUnit.Seconds, "Seconds")]
    [InlineData(DateOffsetUnit.Minutes, "Minutes")]
    [InlineData(DateOffsetUnit.Hours, "Hours")]
    [InlineData(DateOffsetUnit.Days, "Days")]
    public void Generate_DateTimeHotstring_WithOffset_EmitsCorrectUnitString(
        DateOffsetUnit unit, string expectedUnitString)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("t")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy")
            .WithDateOffset(3, unit)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain($"DateAdd(A_Now, 3, \"{expectedUnitString}\")");
    }

    [Fact]
    public void Generate_DateTimeHotstring_WithNegativeOffset_EmitsNegativeAmountUnchanged()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("lastweek")
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy-MM-dd")
            .WithDateOffset(-7, DateOffsetUnit.Days)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain("DateAdd(A_Now, -7, \"Days\")");
    }

    [Theory]
    [InlineData("back`tick", ":X:back``tick::SendText(FormatTime(A_Now, \"yyyy\"))")]
    [InlineData("a ;b", ":X:a `;b::SendText(FormatTime(A_Now, \"yyyy\"))")]
    public void Generate_DateTimeHotstring_TriggerWithSpecialChars_EscapesTriggerToo(
        string trigger, string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger(trigger)
            .WithKind(HotstringKind.DateTime)
            .WithDateTimeFormat("yyyy")
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(expectedLine);
    }

    [Fact]
    public void Generate_MacroHotstring_MergesTextAcrossCursorAndConsecutiveEnterKeys_MatchesSpecExample6()
    {
        // Reconstructed input: spec §7 ex. 6 (`<b>{{cursor}}</b>`) extended with two Enter
        // key tokens so this single golden also proves consecutive-same-key merging.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("htag")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("<b>{{cursor}}</b>{{key:Enter}}{{key:Enter}}")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:htag::\n" +
            "{\n" +
            "\tSendText \"<b></b>\"\n" +
            "\tSend \"{Enter 2}\"\n" +
            "\tSend \"{Left 4}\"\n" +
            "}");
    }

    [Fact]
    public void Generate_MacroHotstring_MergesConsecutiveIdenticalTabKeys()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{key:Tab}}{{key:Tab}}{{key:Tab}}")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "\tSend \"{Tab 3}\"\n" +
            "}");
    }

    [Fact]
    public void Generate_MacroHotstring_MixedEnterThenTab_EmitsTwoSeparateSendLinesInOrder()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{key:Enter}}{{key:Tab}}")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "\tSend \"{Enter}\"\n" +
            "\tSend \"{Tab}\"\n" +
            "}");
    }

    [Fact]
    public void Generate_MacroHotstring_CursorAtEnd_OmitsTrailingLeftLine()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("abc{{cursor}}")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "\tSendText \"abc\"\n" +
            "}");
        output.Should().NotContain("Left");
    }

    [Fact]
    public void Generate_MacroHotstring_CursorOnly_EmitsEmptyBraceBody()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{cursor}}")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(":*:m::\n{\n}");
    }

    [Fact]
    public void Generate_MacroHotstring_MultilineTextRunAfterCursor_EscapesNewlineAndCountsAsOneCharInLeft()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{cursor}}line1\nline2")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "\tSendText \"line1`nline2\"\n" +
            "\tSend \"{Left 11}\"\n" +
            "}");
    }

    [Fact]
    public void Generate_MacroHotstring_EscapesBacktickBeforeQuote_InSendTextString()
    {
        // Escaping quote first would produce a stray "`\"" that a later backtick-escape
        // pass would then double — locking backtick-first ordering in this golden.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("a`b\"c")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain("SendText \"a``b`\"c\"");
    }

    [Fact]
    public void Generate_MacroHotstring_Decision11EscapedLiteralExample_MatchesGolden()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("Dear {{{{first_name}}}},{{key:Enter}}{{cursor}}Alex")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "\tSendText \"Dear {{first_name}},\"\n" +
            "\tSend \"{Enter}\"\n" +
            "\tSendText \"Alex\"\n" +
            "\tSend \"{Left 4}\"\n" +
            "}");
    }

    [Fact]
    public void Generate_MacroHotstring_EscapedLiteralAfterCursor_CountsEmittedLengthInLeft()
    {
        // {{{{first_name}}}} unescapes to the 14-char literal "{{first_name}}" — Left must
        // count that emitted length, not the raw pre-unescape token text.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{cursor}}{{{{first_name}}}}")
            .WithEndingCharacterRequired(false)
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "\tSendText \"{{first_name}}\"\n" +
            "\tSend \"{Left 14}\"\n" +
            "}");
    }

    [Fact]
    public void Generate_TextHotstring_StillEmitsTOption_NoRegression()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithKind(HotstringKind.Text)
            .WithReplacement("by the way")
            .WithTriggerInsideWord(false)
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(":T:btw::by the way");
    }

    [Fact]
    public void Generate_MacroHotstring_NeverEmitsTOption()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Macro)
            .WithReplacement("{{cursor}}")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        int lineEnd = output.IndexOf("::", StringComparison.Ordinal);
        string optionsSegment = output[..lineEnd];
        optionsSegment.Should().NotContain("T");
    }

    [Fact]
    public void Emit_RawKind_EmitsDefinitionVerbatim()
    {
        // Raw's Replacement holds the entire ":opts:trigger::" definition; the emitter returns it
        // verbatim with no option building, escaping, or wrapping.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("~ver")
            .WithKind(HotstringKind.Raw)
            .WithReplacement(":*:~ver::\n{\nMsgBox A_AhkVersion\n}")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:~ver::\n" +
            "{\n" +
            "MsgBox A_AhkVersion\n" +
            "}");
    }

    [Fact]
    public void Emit_RawKindMultilineBody_PreservesLinesVerbatim()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Raw)
            .WithReplacement(":*:m::\n{\nline1\nline2\nline3\n}")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "line1\n" +
            "line2\n" +
            "line3\n" +
            "}");
    }

    [Fact]
    public void Emit_RawKindBody_PreservesInteriorIndentation()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Raw)
            .WithReplacement(":*:m::\n{\nif (true) {\n    MsgBox \"hi\"\n}\n}")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(
            ":*:m::\n" +
            "{\n" +
            "if (true) {\n" +
            "    MsgBox \"hi\"\n" +
            "}\n" +
            "}");
    }

    [Fact]
    public void Emit_RawKindInlineReplacement_EmittedVerbatim()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("ftw")
            .WithKind(HotstringKind.Raw)
            .WithReplacement(":K1000 SE*:ftw::for the win")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Contain(":K1000 SE*:ftw::for the win");
    }

    [Fact]
    public void Emit_RawKind_AddsNoSynthesizedOptions()
    {
        // The emitter never rebuilds an options block for Raw — no T (or any flag) is injected.
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("m")
            .WithKind(HotstringKind.Raw)
            .WithReplacement("::m::\n{\nMsgBox 1\n}")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        int lineEnd = output.IndexOf("::", StringComparison.Ordinal);
        string optionsSegment = output[..lineEnd];
        optionsSegment.Should().NotContain("T");
    }

    [Fact]
    public void Emit_RawKindWithContext_WrapsInHotIfAroundDefinition()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("~ver")
            .WithKind(HotstringKind.Raw)
            .WithReplacement(":*:~ver::\n{\nMsgBox A_AhkVersion\n}")
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_exe notepad.exe\")\n" +
            ":*:~ver::\n" +
            "{\n" +
            "MsgBox A_AhkVersion\n" +
            "}\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_ExecutableContext_WrapsInHotIfWinActiveAhkExe()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "notepad.exe")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_exe notepad.exe\")\n" +
            ":T:btw::by the way\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_WindowClassContext_WrapsInHotIfWinActiveAhkClass()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.WindowClass, "Notepad")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_class Notepad\")\n" +
            ":T:btw::by the way\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_TitleContainsContext_WrapsInHotIfWinActiveBareValue()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(true)
            .WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.TitleContains, "Untitled - Notepad")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"Untitled - Notepad\")\n" +
            ":T:btw::by the way\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_MixedContextAndGlobal_EmitsContextGroupsBeforeGlobalGroup()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        // Trigger-ordinal ("c" < "g") would put the global hotstring first if group
        // ordering didn't take precedence — this test locks in that group order wins.
        Hotstring global = new HotstringBuilder().WithTrigger("g").WithReplacement("global-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false).Build();
        Hotstring ctx = new HotstringBuilder().WithTrigger("c").WithReplacement("ctx-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "app.exe").Build();

        string output = DefaultSut().Generate(profile, [global, ctx], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_exe app.exe\")\n" +
            ":T:c::ctx-rep\n" +
            "#HotIf\n" +
            ":T:g::global-rep\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_MultipleContexts_OrdersGroupsByMatchTypeThenValueOrdinal()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring exeB = new HotstringBuilder().WithTrigger("t1").WithReplacement("r1")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "b.exe").Build();
        Hotstring exeA = new HotstringBuilder().WithTrigger("t2").WithReplacement("r2")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "a.exe").Build();
        Hotstring cls = new HotstringBuilder().WithTrigger("t3").WithReplacement("r3")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.WindowClass, "SomeClass").Build();
        Hotstring title = new HotstringBuilder().WithTrigger("t4").WithReplacement("r4")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.TitleContains, "Zeta").Build();

        string output = DefaultSut().Generate(profile, [exeB, exeA, cls, title], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_exe a.exe\")\n" +
            ":T:t2::r2\n" +
            "#HotIf\n" +
            "#HotIf WinActive(\"ahk_exe b.exe\")\n" +
            ":T:t1::r1\n" +
            "#HotIf\n" +
            "#HotIf WinActive(\"ahk_class SomeClass\")\n" +
            ":T:t3::r3\n" +
            "#HotIf\n" +
            "#HotIf WinActive(\"Zeta\")\n" +
            ":T:t4::r4\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_SameContextTwoHotstrings_SharesOneHotIfBlock()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs1 = new HotstringBuilder().WithTrigger("z").WithReplacement("z-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "app.exe").Build();
        Hotstring hs2 = new HotstringBuilder().WithTrigger("a").WithReplacement("a-rep")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "app.exe").Build();

        string output = DefaultSut().Generate(profile, [hs1, hs2], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_exe app.exe\")\n" +
            ":T:a::a-rep\n" +
            ":T:z::z-rep\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "F");
    }

    [Fact]
    public void Generate_OnlyContextHotstrings_ClosesLastGroupBeforeHotkeysSection()
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder().WithTrigger("t").WithReplacement("r")
            .WithEndingCharacterRequired(true).WithTriggerInsideWord(false)
            .WithContext(WindowMatchType.Executable, "app.exe").Build();
        Hotkey hk = new HotkeyBuilder()
            .WithDescription("d")
            .WithKey("n")
            .WithAction(AHKFlowApp.Domain.Enums.HotkeyAction.Send)
            .WithParameters("hi")
            .Build();

        string output = DefaultSut().Generate(profile, [hs], [hk]);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "#HotIf WinActive(\"ahk_exe app.exe\")\n" +
            ":T:t::r\n" +
            "#HotIf\n" +
            "; --- Hotkeys ---\n" +
            "; d\n" +
            "n::Send(\"hi\")\n" +
            "F");
    }

    private static AhkScriptGenerator TokenSut(string version = "1.2.3")
    {
        IAppVersionProvider ver = Substitute.For<IAppVersionProvider>();
        ver.GetVersion().Returns(version);
        return new AhkScriptGenerator(
            new HeaderTokenRenderer(),
            new FakeTimeProvider(DateTimeOffset.Parse("2026-05-19T12:00:00Z",
                System.Globalization.CultureInfo.InvariantCulture)),
            ver);
    }

    [Fact]
    public void Generate_SubstitutesHeaderTokens()
    {
        AhkScriptGenerator sut = TokenSut();

        Profile p = new ProfileBuilder()
            .WithOwner(Guid.NewGuid())
            .WithName("Work")
            .WithHeader("; {ProfileName} v{AppVersion} — {HotstringCount}h {HotkeyCount}k @ {GeneratedAt:yyyy-MM-dd}\n")
            .WithFooter("")
            .Build();

        Hotstring[] hs =
        [
            new HotstringBuilder().WithOwner(p.OwnerOid).WithTrigger("btw").WithReplacement("by the way").Build(),
        ];

        string output = sut.Generate(p, hs, []);

        output.Should().StartWith("; Work v1.2.3 — 1h 0k @ 2026-05-19");
    }

    [Fact]
    public void Generate_PreservesUnknownTokens_InHeader()
    {
        AhkScriptGenerator sut = TokenSut();
        Profile p = new ProfileBuilder().WithHeader("{Nope} hello\n").WithFooter("").Build();

        string output = sut.Generate(p, [], []);

        output.Should().Contain("{Nope} hello");
    }

    [Fact]
    public void Generate_FooterIsAlsoRendered()
    {
        AhkScriptGenerator sut = TokenSut();
        Profile p = new ProfileBuilder().WithHeader("").WithFooter("; bye v{AppVersion}").Build();

        string output = sut.Generate(p, [], []);

        output.Should().EndWith("; bye v1.2.3");
    }
}
