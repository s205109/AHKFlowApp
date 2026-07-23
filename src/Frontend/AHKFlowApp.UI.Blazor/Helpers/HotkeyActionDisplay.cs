using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Validation;
using MudBlazor;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// Single-sourced label, icon, tint and summary for a hotkey's action, plus the modifier/key
/// combo label. Shared by the desktop grid and the mobile list so the two branches cannot drift.
/// </summary>
internal static class HotkeyActionDisplay
{
    /// <summary>
    /// Warning conveyed to assistive tech and sighted users alike — the chip's warning colour
    /// and icon alone are not exposed to screen readers. Wording is fixed by spec §5: Raw is
    /// not sandboxed, and a syntax error aborts the whole generated profile, not one binding.
    /// </summary>
    public const string RawWarningText =
        "Raw is unchecked AutoHotkey. A mistake here can stop the whole profile script from loading.";

    public static string Label(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => "Send text",
        HotkeyActionKind.SendKeys => "Send keys",
        HotkeyActionKind.Run => "Run",
        HotkeyActionKind.Window => "Window",
        HotkeyActionKind.Remap => "Remap",
        HotkeyActionKind.Disable => "Disable",
        HotkeyActionKind.Raw => "Raw",
        _ => kind.ToString(),
    };

    public static string ChipClass(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => "action-chip--sendtext",
        HotkeyActionKind.SendKeys => "action-chip--sendkeys",
        HotkeyActionKind.Run => "action-chip--run",
        HotkeyActionKind.Window => "action-chip--window",
        HotkeyActionKind.Remap => "action-chip--remap",
        HotkeyActionKind.Disable => "action-chip--disable",
        HotkeyActionKind.Raw => "action-chip--raw",
        _ => "action-chip--sendtext",
    };

    public static string Icon(HotkeyActionKind kind) => kind switch
    {
        HotkeyActionKind.SendText => Icons.Material.Filled.TextFields,
        HotkeyActionKind.SendKeys => Icons.Material.Filled.Keyboard,
        HotkeyActionKind.Run => Icons.Material.Filled.PlayArrow,
        HotkeyActionKind.Window => Icons.Material.Filled.Window,
        HotkeyActionKind.Remap => Icons.Material.Filled.SwapHoriz,
        HotkeyActionKind.Disable => Icons.Material.Filled.Block,
        HotkeyActionKind.Raw => Icons.Material.Filled.Warning,
        _ => Icons.Material.Filled.TextFields,
    };

    public static string WindowOpLabel(WindowOp op) => op switch
    {
        DTOs.WindowOp.Minimize => "Minimize",
        DTOs.WindowOp.Maximize => "Maximize",
        DTOs.WindowOp.Restore => "Restore",
        DTOs.WindowOp.Close => "Close",
        DTOs.WindowOp.ToggleAlwaysOnTop => "Toggle always on top",
        _ => op.ToString(),
    };

    public static string RunTargetKindLabel(RunTargetKind kind) => kind switch
    {
        DTOs.RunTargetKind.Application => "Application",
        DTOs.RunTargetKind.Url => "URL",
        DTOs.RunTargetKind.Folder => "Folder",
        _ => kind.ToString(),
    };

    /// <summary>
    /// Compact modifier + key label, e.g. <c>Ctrl+Alt+S</c>. Modifier order is fixed
    /// Ctrl, Alt, Shift, Win so two rows with the same binding always read identically.
    /// A single-character key is upper-cased for legibility only when paired with a modifier;
    /// a bare key (no modifiers) keeps its original casing, matching AHK's own convention of
    /// writing unmodified single-key hotkeys lowercase. Named keys always keep their spelling.
    /// </summary>
    public static string ComboLabel(HotkeyEditModel item)
    {
        List<string> parts = [];
        if (item.Ctrl) parts.Add("Ctrl");
        if (item.Alt) parts.Add("Alt");
        if (item.Shift) parts.Add("Shift");
        if (item.Win) parts.Add("Win");

        string key = parts.Count > 0 && item.Key.Length == 1
            ? item.Key.ToUpperInvariant()
            : item.Key;
        parts.Add(key);

        return string.Join("+", parts);
    }

    /// <summary>One-line summary of the action's payload for the grid and mobile list.</summary>
    public static string Summary(HotkeyEditModel item) => item.ActionKind switch
    {
        HotkeyActionKind.SendText => FirstLine(item.Text),
        HotkeyActionKind.SendKeys => Plain(item.SendKeysContent),
        HotkeyActionKind.Run => Plain(item.RunTarget),
        HotkeyActionKind.Window => item.WindowOp is { } op ? WindowOpLabel(op) : EmDash,
        HotkeyActionKind.Remap => item.RemapDest is { Length: > 0 } dest ? $"acts as {dest}" : EmDash,
        HotkeyActionKind.Disable => "does nothing",
        HotkeyActionKind.Raw => FirstLine(item.Body),
        _ => EmDash,
    };

    private const string EmDash = "—";

    private static string Plain(string? value) =>
        string.IsNullOrWhiteSpace(value) ? EmDash : value;

    // Multi-line payloads collapse to their first line with an ellipsis, so a grid row never
    // grows to the height of a whole replacement block.
    private static string FirstLine(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return EmDash;

        int newline = value.IndexOf('\n');
        if (newline < 0)
            return value.Trim();

        return $"{value[..newline].Trim()}…";
    }
}
