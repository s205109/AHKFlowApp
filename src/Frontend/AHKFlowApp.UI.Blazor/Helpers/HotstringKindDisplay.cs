using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>Single-sourced label and tint class for a hotstring's kind chip, shared by the
/// desktop grid and the mobile list so both branches show the same Type coding.</summary>
internal static class HotstringKindDisplay
{
    /// <summary>Warning conveyed to assistive tech and sighted users alike — the chip's warning
    /// color and icon alone are not exposed to screen readers.</summary>
    public const string ScriptWarningText = "Verbatim AutoHotkey definition — review before running.";

    public static string Label(HotstringKind kind) => kind switch
    {
        HotstringKind.Text => "Text",
        HotstringKind.DateTime => "Date & time",
        HotstringKind.Macro => "Macro",
        HotstringKind.Raw => "Raw",
        _ => kind.ToString(),
    };

    public static string ChipClass(HotstringKind kind) => kind switch
    {
        HotstringKind.DateTime => "kind-chip--datetime",
        HotstringKind.Macro => "kind-chip--macro",
        HotstringKind.Raw => "kind-chip--raw",
        _ => "kind-chip--text",
    };
}
