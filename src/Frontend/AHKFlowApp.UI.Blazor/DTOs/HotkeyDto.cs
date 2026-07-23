namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotkeyDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyActionKind ActionKind,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[]? CategoryIds = null,
    // Legacy pair — retires in Task 10 once no consumer reads it. The API no longer sends
    // these; they exist so the frontend compiles while consumers migrate one task at a time.
    HotkeyAction Action = HotkeyAction.Send,
    string Parameters = "");
