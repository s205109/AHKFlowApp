using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>Point-in-time snapshot of a hotstring aggregate, stored as history JSON.</summary>
/// <param name="Trigger">Abbreviation that activated the replacement.</param>
/// <param name="Replacement">Text that replaced the trigger.</param>
/// <param name="Description">Optional human-readable note.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applied to every profile.</param>
/// <param name="IsEndingCharacterRequired">AutoHotkey ending-character option at capture time.</param>
/// <param name="IsTriggerInsideWord">AutoHotkey inside-word option at capture time.</param>
/// <param name="ProfileIds">Profile links at capture time.</param>
/// <param name="CategoryIds">Category links at capture time.</param>
/// <param name="CreatedAt">Original creation timestamp.</param>
/// <param name="UpdatedAt">Last-update timestamp at capture time.</param>
public sealed record HotstringSnapshot(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Point-in-time snapshot of a hotkey aggregate, stored as history JSON.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific parameter payload.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applied to every profile.</param>
/// <param name="ProfileIds">Profile links at capture time.</param>
/// <param name="CategoryIds">Category links at capture time.</param>
/// <param name="CreatedAt">Original creation timestamp.</param>
/// <param name="UpdatedAt">Last-update timestamp at capture time.</param>
public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);
