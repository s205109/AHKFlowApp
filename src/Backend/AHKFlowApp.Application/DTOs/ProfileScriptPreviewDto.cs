namespace AHKFlowApp.Application.DTOs;

public sealed record ProfileScriptPreviewDto(
    string Script,
    int HotstringCount,
    int HotkeyCount,
    DateTimeOffset GeneratedAt);
