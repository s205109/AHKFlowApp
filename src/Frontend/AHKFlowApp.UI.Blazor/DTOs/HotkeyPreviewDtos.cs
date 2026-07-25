namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>Draft hotkey fields to preview, without saving. Mirror of the backend DTO.</summary>
public sealed record HotkeyPreviewRequestDto(
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
    string? Body = null);

/// <summary>The AutoHotkey snippet a hotkey draft would generate. Mirror of the backend DTO.</summary>
public sealed record HotkeyPreviewDto(string Snippet);
