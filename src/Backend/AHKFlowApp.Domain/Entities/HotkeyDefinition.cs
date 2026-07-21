using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotkey, grouped so factory signatures stay stable as actions
/// and options grow across the redesign waves. Mirrors <see cref="HotstringDefinition"/>.
/// </summary>
public sealed record HotkeyDefinition(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles);
