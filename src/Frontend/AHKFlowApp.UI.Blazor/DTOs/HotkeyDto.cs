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
    WindowMatchType? ContextMatchType,
    string? ContextValue,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[]? CategoryIds = null,
    // The rules a Restore's stored snapshot failed, when the item came back applying to no
    // profile. Null or empty on every other response. The name matches the backend DTO, so
    // System.Text.Json binds it with no attribute.
    string[]? RestoreWarnings = null);
