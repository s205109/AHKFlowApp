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

    [Fact]
    public void Parse_ReadsAWildcardHotkeyAndItsKeyUpHalfAsOneKey()
    {
        TemplateKeyUses.Parse(CapsLockLayer).Should().Equal("CapsLock");
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
    public void Parse_IgnoresALineCarryingItsOwnModifiers()
    {
        TemplateKeyUses.Parse("""^!c::Run "calc.exe" """).Should().BeEmpty();
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
        TemplateKeyUses.Parse("""CapsLock::Send "hello" """).Should().Equal("CapsLock");
    }

    [Fact]
    public void Parse_ReadsATildePrefixedHotkey()
    {
        TemplateKeyUses.Parse("~ScrollLock::Reload").Should().Equal("ScrollLock");
    }

    [Fact]
    public void Parse_KeepsOneEntryPerKeyIgnoringCase()
    {
        TemplateKeyUses.Parse("*CapsLock::\n*capslock up::").Should().Equal("CapsLock");
    }
}
