using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotkey lines, mirroring <see cref="HotstringEmitter"/>. The left-hand
/// side is the auto <c>$</c> (SendKeys on a keyboard key) + modifiers in the fixed order <c>^ ! + #</c>
/// + the key; the right-hand side is per <see cref="HotkeyActionKind"/> (spec §1).
/// </summary>
/// <remarks>
/// Everything embedded in a quoted literal (<c>SendText</c>, <c>SendKeys</c>, <c>Run</c>) passes
/// through <see cref="AhkEscaping.EscapeStringLiteral"/>. Token validation and string-literal
/// escaping are separate layers: <c>"</c> and <c>`</c> are legal one-character SendKeys tokens
/// (Send types them), so a validated token still has to be escaped or it terminates the literal.
/// Remap emits a bare validated key name — no literal, nothing to escape. Raw emits <c>Body</c>
/// verbatim — the sole unchecked path; a block body carries its own braces (2026-07-22 decision,
/// see spec Raw emission note — preserves byte-identity for converted legacy <c>Send</c> rows).
/// </remarks>
internal static class HotkeyEmitter
{
    private const string ActiveWindow = "\"A\"";

    public static string Emit(Hotkey hk)
    {
        string rhs = hk.ActionKind switch
        {
            HotkeyActionKind.SendText => $"SendText(\"{AhkEscaping.EscapeStringLiteral(hk.Text ?? "")}\")",
            HotkeyActionKind.SendKeys => $"Send(\"{AhkEscaping.EscapeStringLiteral(hk.SendKeysContent ?? "")}\")",
            HotkeyActionKind.Run => $"Run(\"{AhkEscaping.EscapeStringLiteral(hk.RunTarget ?? "")}\")",
            HotkeyActionKind.Window => WindowCall(hk.WindowOp),
            HotkeyActionKind.Remap => RemapRhs(hk.RemapDest),
            HotkeyActionKind.Disable => "return",
            HotkeyActionKind.Raw => hk.Body ?? "",
            _ => throw new InvalidOperationException($"Unsupported HotkeyActionKind: {hk.ActionKind}"),
        };

        return $"{Prefix(hk)}{BuildModifiers(hk)}{hk.Key}::{rhs}";
    }

    private static string WindowCall(WindowOp? op) => op switch
    {
        WindowOp.Minimize => $"WinMinimize({ActiveWindow})",
        WindowOp.Maximize => $"WinMaximize({ActiveWindow})",
        WindowOp.Restore => $"WinRestore({ActiveWindow})",
        WindowOp.Close => $"WinClose({ActiveWindow})",
        WindowOp.ToggleAlwaysOnTop => $"WinSetAlwaysOnTop(-1, {ActiveWindow})",
        _ => throw new InvalidOperationException($"Unsupported WindowOp: {op}"),
    };

    private static string RemapRhs(string? dest) =>
        dest ?? throw new InvalidOperationException("Remap requires a RemapDest");

    // $ forces the keyboard hook so a SendKeys binding cannot retrigger the script's own hotkeys
    // (spec §5). Emitted for every SendKeys on a keyboard key. Mouse/wheel keys (Wave 2) use the
    // mouse hook already and get no $ — until then, all registry keys are keyboard keys.
    private static string Prefix(Hotkey hk) =>
        hk.ActionKind == HotkeyActionKind.SendKeys ? "$" : "";

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
