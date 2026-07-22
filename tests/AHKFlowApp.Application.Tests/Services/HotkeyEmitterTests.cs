using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class HotkeyEmitterTests
{
    [Fact] // golden 1
    public void Emit_Run_App() =>
        Line(new HotkeyBuilder().WithKey("n").WithWin().WithRun("notepad"))
            .Should().Be("#n::Run(\"notepad\")");

    [Fact] // golden 2
    public void Emit_Run_ModifiersInFixedOrder() =>
        Line(new HotkeyBuilder().WithKey("c").WithCtrl().WithAlt().WithRun("calc.exe"))
            .Should().Be("^!c::Run(\"calc.exe\")");

    [Fact] // golden 4 — URL is the same emission as app
    public void Emit_Run_Url() =>
        Line(new HotkeyBuilder().WithKey("j").WithWin().WithRun("https://github.com", RunTargetKind.Url))
            .Should().Be("#j::Run(\"https://github.com\")");

    [Fact] // golden 5
    public void Emit_Window_AlwaysOnTop() =>
        Line(new HotkeyBuilder().WithKey("Space").WithCtrl().WithWindow(WindowOp.ToggleAlwaysOnTop))
            .Should().Be("^Space::WinSetAlwaysOnTop(-1, \"A\")");

    [Fact] // golden 6
    public void Emit_Window_Minimize() =>
        Line(new HotkeyBuilder().WithKey("Down").WithWin().WithWindow(WindowOp.Minimize))
            .Should().Be("#Down::WinMinimize(\"A\")");

    [Fact] // golden 7
    public void Emit_Window_Maximize() =>
        Line(new HotkeyBuilder().WithKey("Up").WithWin().WithWindow(WindowOp.Maximize))
            .Should().Be("#Up::WinMaximize(\"A\")");

    [Fact] // golden 8
    public void Emit_Window_Close() =>
        Line(new HotkeyBuilder().WithKey("w").WithCtrl().WithAlt().WithWindow(WindowOp.Close))
            .Should().Be("^!w::WinClose(\"A\")");

    [Fact]
    public void Emit_Window_Restore() =>
        Line(new HotkeyBuilder().WithKey("r").WithWin().WithWindow(WindowOp.Restore))
            .Should().Be("#r::WinRestore(\"A\")");

    [Fact] // golden 9 — SendText escapes free text (backtick-n from a newline)
    public void Emit_SendText_EscapesMultiline() =>
        Line(new HotkeyBuilder().WithKey("s").WithCtrl().WithAlt().WithSendText("Jane Smith\nAcme"))
            .Should().Be("^!s::SendText(\"Jane Smith`nAcme\")");

    [Fact]
    public void Emit_SendText_EscapesQuoteAndBacktick() =>
        Line(new HotkeyBuilder().WithKey("a").WithCtrl().WithSendText("he said \"hi\" 100`%"))
            .Should().Be("^a::SendText(\"he said `\"hi`\" 100``%\")");

    [Fact] // golden 11 — SendKeys gets the auto $ prefix on a keyboard key
    public void Emit_SendKeys_MediaKey_AutoDollar() =>
        Line(new HotkeyBuilder().WithKey("p").WithWin().WithSendKeys("{Media_Play_Pause}"))
            .Should().Be("$#p::Send(\"{Media_Play_Pause}\")");

    [Fact] // golden 12
    public void Emit_SendKeys_VolumeKey_AutoDollar() =>
        Line(new HotkeyBuilder().WithKey("Up").WithCtrl().WithAlt().WithSendKeys("{Volume_Up}"))
            .Should().Be("$^!Up::Send(\"{Volume_Up}\")");

    // Quote and backtick are valid one-character SendKeys tokens; unescaped they would emit
    // Send(""") and Send("`") — both refuse to load. Escaping happens at the literal layer.
    [Theory]
    [InlineData("\"", "$a::Send(\"`\"\")")]
    [InlineData("`", "$a::Send(\"``\")")]
    public void Emit_SendKeys_EscapesLiteralHostileToken(string token, string expected) =>
        Line(new HotkeyBuilder().WithKey("a").WithSendKeys(token))
            .Should().Be(expected);

    [Fact] // the $ prefix belongs to SendKeys only — no other kind gets it
    public void Emit_NonSendKeysKind_HasNoDollarPrefix() =>
        Line(new HotkeyBuilder().WithKey("a").WithSendText("x"))
            .Should().NotStartWith("$");

    [Fact] // golden 13
    public void Emit_Remap_BareKey() =>
        Line(new HotkeyBuilder().WithKey("CapsLock").WithRemap("Ctrl"))
            .Should().Be("CapsLock::Ctrl");

    [Fact] // golden 15
    public void Emit_Disable() =>
        Line(new HotkeyBuilder().WithKey("F1").WithDisable())
            .Should().Be("F1::return");

    [Fact] // golden 10 body — Raw wraps a verbatim body in braces
    public void Emit_Raw_WrapsBody() =>
        Line(new HotkeyBuilder().WithKey("v").WithCtrl().WithShift().WithRawBody("\n\tSendText A_Clipboard\n"))
            .Should().Be("^+v::{\n\tSendText A_Clipboard\n}");

    [Fact] // Raw is the sole verbatim path — a quote in the body is NOT re-escaped
    public void Emit_Raw_DoesNotEscapeBody() =>
        Line(new HotkeyBuilder().WithKey("a").WithRawBody("\nMsgBox \"hi\"\n"))
            .Should().Be("a::{\nMsgBox \"hi\"\n}");

    [Fact]
    public void Emit_UnsupportedKind_Throws()
    {
        Hotkey hk = new HotkeyBuilder().WithKey("a").Build();
        typeof(Hotkey).GetProperty("ActionKind")!.SetValue(hk, (HotkeyActionKind)99);

        Action act = () => HotkeyEmitter.Emit(hk);

        act.Should().Throw<InvalidOperationException>().WithMessage("*99*");
    }

    [Fact]
    public void Emit_WindowKindWithoutOp_Throws()
    {
        Hotkey hk = new HotkeyBuilder().WithKey("a").WithWindow(WindowOp.Close).Build();
        typeof(Hotkey).GetProperty("WindowOp")!.SetValue(hk, null);

        Action act = () => HotkeyEmitter.Emit(hk);

        act.Should().Throw<InvalidOperationException>().WithMessage("*WindowOp*");
    }

    private static string Line(HotkeyBuilder b) => HotkeyEmitter.Emit(b.Build());
}
