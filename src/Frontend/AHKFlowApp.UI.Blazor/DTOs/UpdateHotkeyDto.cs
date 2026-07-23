namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record UpdateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    Guid[]? CategoryIds = null,
    // Legacy pair — retires in Task 10. Serialized but ignored by the typed API.
    HotkeyAction Action = HotkeyAction.Send,
    string Parameters = "");
