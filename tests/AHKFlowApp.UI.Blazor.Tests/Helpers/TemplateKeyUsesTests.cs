using AHKFlowApp.UI.Blazor.Helpers;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class TemplateKeyUsesTests
{
    // The shipped capslock-modifier-layer preset body, copied from
    // src/Backend/AHKFlowApp.Application/Constants/HeaderPresetCatalog.cs.
    private const string CapsLockLayer = """
        ; Hold Caps Lock to press Ctrl, Alt and Shift together.
        SetCapsLockState "AlwaysOff"

        *CapsLock::
        {
            SetKeyDelay -1
            Send "{Blind}{LCtrl DownR}{LAlt DownR}{LShift DownR}"
        }

        *CapsLock up::
        {
            SetKeyDelay -1
            Send "{Blind}{LCtrl Up}{LAlt Up}{LShift Up}"
        }
        """;

    private static TemplateHotkey Plain(string key) => new(key, false, false, false, false, false);

    private static TemplateHotkey Wildcard(string key) => new(key, true, false, false, false, false);

    [Fact]
    public void Parse_ReadsAWildcardHotkeyAndItsKeyUpHalfAsOneKey()
    {
        TemplateKeyUses.Parse(CapsLockLayer).Should().Equal(Wildcard("CapsLock"));
    }

    [Fact]
    public void Parse_IgnoresDirectivesAndFunctionCalls()
    {
        const string header = """
            ; Work — AHKFlowApp v1.2.3
            #Requires AutoHotkey v2.0
            #SingleInstance Force
            SendMode "Input"
            SetWorkingDir A_ScriptDir
            """;

        TemplateKeyUses.Parse(header).Should().BeEmpty();
    }

    [Fact]
    public void Parse_ReadsTheModifiersALineCarries()
    {
        TemplateKeyUses.Parse("""^!c::Run "calc.exe" """)
            .Should().Equal(new TemplateHotkey("c", false, true, true, false, false));
    }

    [Fact]
    public void Parse_ReadsASideSpecificModifierAsThatModifier()
    {
        // A row cannot say "left Ctrl only", so the side is dropped. The two hotkeys still overlap:
        // holding left Ctrl presses both.
        TemplateKeyUses.Parse("<^a::MsgBox \"left\"")
            .Should().Equal(new TemplateHotkey("a", false, true, false, false, false));
    }

    [Fact]
    public void Parse_ReadsAWildcardHotkeyThatAlsoCarriesModifiers()
    {
        TemplateKeyUses.Parse("*#e::Run \"explorer.exe\"")
            .Should().Equal(new TemplateHotkey("e", true, false, false, false, true));
    }

    [Fact]
    public void Parse_IgnoresACustomCombination()
    {
        TemplateKeyUses.Parse("""LCtrl & RAlt::MsgBox "AltGr" """).Should().BeEmpty();
    }

    [Fact]
    public void Parse_IgnoresACommentThatLooksLikeAHotkey()
    {
        TemplateKeyUses.Parse("; *CapsLock::").Should().BeEmpty();
    }

    [Fact]
    public void Parse_IgnoresADoubleColonInsideAStringLiteral()
    {
        TemplateKeyUses.Parse("""MsgBox "a::b" """).Should().BeEmpty();
    }

    [Fact]
    public void Parse_IgnoresAHotstring()
    {
        TemplateKeyUses.Parse("::btw::by the way").Should().BeEmpty();
    }

    [Fact]
    public void Parse_ReadsAPlainHotkeyWithNoPrefix()
    {
        TemplateKeyUses.Parse("""CapsLock::Send "hello" """).Should().Equal(Plain("CapsLock"));
    }

    [Fact]
    public void Parse_ReadsATildePrefixedHotkey()
    {
        TemplateKeyUses.Parse("~ScrollLock::Reload").Should().Equal(Plain("ScrollLock"));
    }

    [Fact]
    public void Parse_KeepsOneEntryPerKeyIgnoringCase()
    {
        TemplateKeyUses.Parse("*CapsLock::\n*capslock up::").Should().Equal(Wildcard("CapsLock"));
    }

    [Fact]
    public void Parse_KeepsTwoEntriesWhenTheSameKeyCarriesDifferentModifiers()
    {
        TemplateKeyUses.Parse("^c::\n^!c::")
            .Should().Equal(
                new TemplateHotkey("c", false, true, false, false, false),
                new TemplateHotkey("c", false, true, true, false, false));
    }
}
