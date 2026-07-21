using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using AHKFlowApp.TestUtilities.Builders;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Services;

public sealed class HotkeyEmitterTests
{
    [Fact]
    public void Emit_RunAction_EmitsRunCall()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("n")
            .WithWin()
            .WithAction(HotkeyAction.Run)
            .WithParameters("notepad")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().Be("#n::Run(\"notepad\")");
    }

    [Fact]
    public void Emit_ModifiersSet_EmitsInFixedCtrlAltShiftWinOrder()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("c")
            .WithCtrl().WithAlt().WithShift().WithWin()
            .WithAction(HotkeyAction.Run)
            .WithParameters("calc.exe")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().StartWith("^!+#c::");
    }

    [Fact]
    public void Emit_ParametersContainDoubleQuote_AreEscaped()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("a")
            .WithCtrl()
            .WithAction(HotkeyAction.Send)
            .WithParameters("he said \"hi\"")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().Be("^a::Send(\"he said `\"hi`\"\")");
    }

    [Fact]
    public void Emit_ParametersContainBacktick_AreEscaped()
    {
        Hotkey hk = new HotkeyBuilder()
            .WithKey("a")
            .WithCtrl()
            .WithAction(HotkeyAction.Send)
            .WithParameters("100`% done")
            .Build();

        string line = HotkeyEmitter.Emit(hk);

        line.Should().Be("^a::Send(\"100``% done\")");
    }

    [Fact]
    public void Emit_UnsupportedAction_Throws()
    {
        Hotkey hk = new HotkeyBuilder().WithAction((HotkeyAction)99).Build();

        Action act = () => HotkeyEmitter.Emit(hk);

        act.Should().Throw<InvalidOperationException>()
            .WithMessage("*99*");
    }
}
