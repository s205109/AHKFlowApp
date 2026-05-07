using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class AhkScriptGeneratorTests
{
    private readonly AhkScriptGenerator _sut = new();

    [Fact]
    public void Generate_EmptyProfile_EmitsHeaderSectionMarkersAndFooter()
    {
        Profile profile = new ProfileBuilder()
            .WithHeader("#Requires AutoHotkey v2.0")
            .WithFooter("; end of file")
            .Build();

        string output = _sut.Generate(profile, [], []);

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

        string output = _sut.Generate(profile, [], []);

        output.Should().Be(
            "\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n");
    }

    [Theory]
    [InlineData(true, false, "::btw::by the way")]                  // default — no options
    [InlineData(false, false, ":*:btw::by the way")]                // ending char NOT required
    [InlineData(true, true, ":?:btw::by the way")]                  // trigger inside word
    [InlineData(false, true, ":*?:btw::by the way")]                // both options
    public void Generate_Hotstring_FormatsOptionsCorrectly(
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        string expectedLine)
    {
        Profile profile = new ProfileBuilder().WithHeader("H").WithFooter("F").Build();
        Hotstring hs = new HotstringBuilder()
            .WithTrigger("btw")
            .WithReplacement("by the way")
            .WithEndingCharacterRequired(isEndingCharacterRequired)
            .WithTriggerInsideWord(isTriggerInsideWord)
            .Build();

        string output = _sut.Generate(profile, [hs], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            expectedLine + "\n" +
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

        string output = _sut.Generate(profile, [hs1, hs2], []);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "::a::alpha\n" +
            "::b::beta\n" +
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

        string output = _sut.Generate(profile, [], [hk]);

        output.Should().Be(
            "H\n" +
            "; --- Hotstrings ---\n" +
            "; --- Hotkeys ---\n" +
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

        string output = _sut.Generate(profile, [], [hk]);

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

        string output = _sut.Generate(profile, [], [hk]);

        output.Should().Contain("^a::Send(\"he said \"hi\"\")");
    }
}
