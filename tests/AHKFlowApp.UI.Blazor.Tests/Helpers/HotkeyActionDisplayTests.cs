using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Helpers;
using AHKFlowApp.UI.Blazor.Validation;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Helpers;

public sealed class HotkeyActionDisplayTests
{
    [Theory]
    [InlineData(HotkeyActionKind.SendText, "Send text")]
    [InlineData(HotkeyActionKind.SendKeys, "Send keys")]
    [InlineData(HotkeyActionKind.Run, "Run")]
    [InlineData(HotkeyActionKind.Window, "Window")]
    [InlineData(HotkeyActionKind.Remap, "Remap")]
    [InlineData(HotkeyActionKind.Disable, "Disable")]
    [InlineData(HotkeyActionKind.Raw, "Raw")]
    public void Label_IsHumanReadablePerKind(HotkeyActionKind kind, string expected) =>
        HotkeyActionDisplay.Label(kind).Should().Be(expected);

    [Theory]
    [InlineData(false, false, false, false, "n", "n")]
    [InlineData(true, false, false, false, "c", "Ctrl+C")]
    [InlineData(true, true, false, false, "s", "Ctrl+Alt+S")]
    [InlineData(false, false, false, true, "n", "Win+N")]
    [InlineData(true, true, true, true, "Space", "Ctrl+Alt+Shift+Win+Space")]
    public void ComboLabel_OrdersModifiersCtrlAltShiftWin(
        bool ctrl, bool alt, bool shift, bool win, string key, string expected)
    {
        var model = new HotkeyEditModel { Ctrl = ctrl, Alt = alt, Shift = shift, Win = win, Key = key };

        HotkeyActionDisplay.ComboLabel(model).Should().Be(expected);
    }

    [Fact]
    public void ComboLabel_Snapshot_MatchesEditModelCasing()
    {
        var snapshot = new HotkeySnapshot(
            Description: "Test", Key: "n", Ctrl: true, Alt: false, Shift: false, Win: false,
            ActionKind: HotkeyActionKind.SendText, Text: null, SendKeysContent: null, RunTarget: null,
            RunTargetKind: null, WindowOp: null, RemapDest: null, Body: null,
            AppliesToAllProfiles: true, ProfileIds: [], CategoryIds: [],
            CreatedAt: DateTimeOffset.UnixEpoch, UpdatedAt: DateTimeOffset.UnixEpoch);

        HotkeyActionDisplay.ComboLabel(snapshot).Should().Be("Ctrl+N");
    }

    [Fact]
    public void ComboLabel_DeletedHotkeyDto_MatchesEditModelCasing()
    {
        var dto = new DeletedHotkeyDto(
            Id: Guid.NewGuid(), Description: "Test", Key: "n",
            Ctrl: true, Alt: false, Shift: false, Win: false, DeletedAt: DateTimeOffset.UnixEpoch);

        HotkeyActionDisplay.ComboLabel(dto).Should().Be("Ctrl+N");
    }

    [Fact]
    public void Summary_SendText_IsFirstLineWithEllipsis()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.SendText, Text = "Jane Smith\nAcme" };

        HotkeyActionDisplay.Summary(model).Should().Be("Jane Smith…");
    }

    [Fact]
    public void Summary_Run_IsTarget()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Run, RunTarget = "notepad" };

        HotkeyActionDisplay.Summary(model).Should().Be("notepad");
    }

    [Fact]
    public void Summary_Window_IsOperationLabel()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Window, WindowOp = WindowOp.ToggleAlwaysOnTop };

        HotkeyActionDisplay.Summary(model).Should().Be("Toggle always on top");
    }

    [Fact]
    public void Summary_Remap_ShowsDestination()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Remap, RemapDest = "Ctrl" };

        HotkeyActionDisplay.Summary(model).Should().Be("acts as Ctrl");
    }

    [Fact]
    public void Summary_Disable_IsFixedPhrase()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Disable };

        HotkeyActionDisplay.Summary(model).Should().Be("does nothing");
    }

    [Fact]
    public void Summary_Raw_IsFirstBodyLine()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Raw, Body = "  MsgBox \"hi\"\n  Sleep 100" };

        HotkeyActionDisplay.Summary(model).Should().Be("MsgBox \"hi\"…");
    }

    [Fact]
    public void Summary_MissingPayload_IsEmDash()
    {
        var model = new HotkeyEditModel { ActionKind = HotkeyActionKind.Run, RunTarget = null };

        HotkeyActionDisplay.Summary(model).Should().Be("—");
    }
}
