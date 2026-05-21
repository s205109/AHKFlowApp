namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record ProfileScriptPreviewDto(
    string Script,
    int HotstringCount,
    int HotkeyCount,
    DateTimeOffset GeneratedAt);
