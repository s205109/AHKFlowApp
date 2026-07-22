using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotkey, grouped so factory signatures stay stable as actions and options
/// grow across the redesign waves. Mirrors <see cref="HotstringDefinition"/>.
/// </summary>
/// <remarks>
/// During Wave 1 the legacy <see cref="Action"/> / <see cref="Parameters"/> pair and the typed
/// columns coexist (expand phase). The legacy pair is removed in the contract task once every write
/// path and the emitter read the typed columns.
/// </remarks>
public sealed record HotkeyDefinition(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles,
    HotkeyActionKind ActionKind = HotkeyActionKind.Raw,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null);
