using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotkey lines, mirroring <see cref="HotstringEmitter"/>.
/// The left-hand side is modifiers in the fixed order <c>^ ! + #</c> followed by the key;
/// the right-hand side is the action call.
/// </summary>
/// <remarks>
/// Every free-text value passes through <see cref="AhkEscaping.EscapeStringLiteral"/>.
/// Because the generator and the profile download both route through here, escaping
/// reaches rows written by paths that never see a validator — history restore, history
/// revert, and the development lazy seed.
/// </remarks>
internal static class HotkeyEmitter
{
    public static string Emit(Hotkey hk)
    {
        string function = hk.Action switch
        {
            HotkeyAction.Send => "Send",
            HotkeyAction.Run => "Run",
            _ => throw new InvalidOperationException($"Unsupported HotkeyAction: {hk.Action}"),
        };

        return $"{BuildModifiers(hk)}{hk.Key}::{function}(\"{AhkEscaping.EscapeStringLiteral(hk.Parameters)}\")";
    }

    private static string BuildModifiers(Hotkey hk)
    {
        string modifiers = "";
        if (hk.Ctrl) modifiers += "^";
        if (hk.Alt) modifiers += "!";
        if (hk.Shift) modifiers += "+";
        if (hk.Win) modifiers += "#";
        return modifiers;
    }
}
