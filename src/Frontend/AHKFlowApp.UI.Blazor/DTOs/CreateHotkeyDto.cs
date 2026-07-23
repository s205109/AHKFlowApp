namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record CreateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    Guid[]? CategoryIds = null);
