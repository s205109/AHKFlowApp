using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotkey, grouped so factory signatures stay stable as actions and options
/// grow across the redesign waves. Mirrors <see cref="HotstringDefinition"/>.
/// </summary>
/// <remarks>
/// Typed-only since the Wave 1 contract phase: the legacy <c>Action</c> / <c>Parameters</c> pair was
/// dropped once every write path and the emitter read the typed columns. Legacy input still reaching
/// the system (pre-W1 history snapshots) is translated by
/// <c>LegacyHotkeyDefinitionConverter</c> before a definition is built.
/// </remarks>
public sealed record HotkeyDefinition(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyActionKind ActionKind,
    bool AppliesToAllProfiles,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null);
