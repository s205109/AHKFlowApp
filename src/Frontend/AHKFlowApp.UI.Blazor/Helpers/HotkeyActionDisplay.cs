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

    /// <summary>Stands in for the kind of a pre-typed-action history snapshot, which has none.</summary>
    public const string LegacyLabel = "Legacy";

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
    public static string ComboLabel(HotkeyEditModel item) =>
        ComboLabel(item.Key, item.Ctrl, item.Alt, item.Shift, item.Win);

    /// <summary>Combo label for a history snapshot — see <see cref="ComboLabel(HotkeyEditModel)"/>.</summary>
    public static string ComboLabel(HotkeySnapshot snapshot) =>
        ComboLabel(snapshot.Key, snapshot.Ctrl, snapshot.Alt, snapshot.Shift, snapshot.Win);

    /// <summary>Combo label for a deleted hotkey row — see <see cref="ComboLabel(HotkeyEditModel)"/>.</summary>
    public static string ComboLabel(DeletedHotkeyDto dto) =>
        ComboLabel(dto.Key, dto.Ctrl, dto.Alt, dto.Shift, dto.Win);

    private static string ComboLabel(string key, bool ctrl, bool alt, bool shift, bool win)
    {
        List<string> parts = [];
        if (ctrl) parts.Add("Ctrl");
        if (alt) parts.Add("Alt");
        if (shift) parts.Add("Shift");
        if (win) parts.Add("Win");

        string label = parts.Count > 0 && key.Length == 1
            ? key.ToUpperInvariant()
            : key;
        parts.Add(label);

        return string.Join("+", parts);
    }

    /// <summary>One-line summary of the action's payload for the grid and mobile list.</summary>
    public static string Summary(HotkeyEditModel item) =>
        Summarize(item.ActionKind, item.Text, item.SendKeysContent, item.RunTarget,
            item.WindowOp, item.RemapDest, item.Body);

    /// <summary>
    /// Kind label for a history snapshot. A legacy snapshot carries no meaningful
    /// <c>ActionKind</c>: stored history JSON predates the field, so it deserializes to the
    /// record's default — <see cref="HotkeyActionKind.Raw"/> — and the backend replays snapshots
    /// verbatim (it only converts on revert). Labelling those "Raw" would put this UI's
    /// script-safety wording on rows that are nothing of the sort, so they read "Legacy" instead.
    /// The kind is not mapped from the legacy action either: <see cref="SummaryOf"/> already
    /// prints that word, and mapping here would render "Run — Run notepad.exe".
    /// </summary>
    public static string LabelOf(HotkeySnapshot snapshot) =>
        snapshot.Action is not null ? LegacyLabel : Label(snapshot.ActionKind);

    /// <summary>
    /// Summary for a history snapshot. Legacy snapshots (pre-typed-action rows) carry only the
    /// old Action/Parameters pair, so they fall back to showing that verbatim.
    /// </summary>
    public static string SummaryOf(HotkeySnapshot snapshot) =>
        snapshot.Action is not null
            ? $"{snapshot.Action} {snapshot.Parameters}".Trim()
            : Summarize(snapshot.ActionKind, snapshot.Text, snapshot.SendKeysContent,
                snapshot.RunTarget, snapshot.WindowOp, snapshot.RemapDest, snapshot.Body);

    // The one switch both overloads share — a snapshot and an edit model are different types
    // carrying the same seven fields, and two copies of this would drift.
    private static string Summarize(
        HotkeyActionKind kind, string? text, string? sendKeysContent, string? runTarget,
        WindowOp? windowOp, string? remapDest, string? body) => kind switch
        {
            HotkeyActionKind.SendText => FirstLine(text),
            HotkeyActionKind.SendKeys => Plain(sendKeysContent),
            HotkeyActionKind.Run => Plain(runTarget),
            HotkeyActionKind.Window => windowOp is { } op ? WindowOpLabel(op) : EmDash,
            HotkeyActionKind.Remap => remapDest is { Length: > 0 } dest ? $"acts as {dest}" : EmDash,
            HotkeyActionKind.Disable => "does nothing",
            HotkeyActionKind.Raw => FirstLine(body),
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
