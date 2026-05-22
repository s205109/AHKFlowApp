namespace AHKFlowApp.Application.DTOs;

/// <summary>Preview of a generated AutoHotkey script without downloading it.</summary>
/// <param name="Script">Rendered script body.</param>
/// <param name="HotstringCount">Number of hotstrings included in the script.</param>
/// <param name="HotkeyCount">Number of hotkeys included in the script.</param>
/// <param name="GeneratedAt">UTC timestamp when the preview was generated.</param>
public sealed record ProfileScriptPreviewDto(
    string Script,
    int HotstringCount,
    int HotkeyCount,
    DateTimeOffset GeneratedAt);
