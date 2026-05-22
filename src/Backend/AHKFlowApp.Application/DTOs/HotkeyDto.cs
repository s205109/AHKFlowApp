using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>A keyboard hotkey binding owned by the current user.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="ProfileIds">Profiles the hotkey is attached to.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey is included in every profile the user owns.</param>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">The main key, such as <c>F1</c> or <c>a</c>.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific parameter payload, such as text to send or a command to run.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
/// <param name="CategoryIds">Categories assigned to this hotkey.</param>
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
    HotkeyAction Action,
    string Parameters,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[] CategoryIds);

/// <summary>Payload to create a new hotkey.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific payload.</param>
/// <param name="ProfileIds">Profiles to attach the new hotkey to.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applies to every profile.</param>
/// <param name="CategoryIds">Categories to assign to the new hotkey.</param>
public sealed record CreateHotkeyDto(
    string Description,
    string Key,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    HotkeyAction Action = HotkeyAction.Send,
    string Parameters = "",
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    Guid[]? CategoryIds = null);

/// <summary>Payload to replace the editable fields of an existing hotkey.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Action">Action kind performed when the hotkey fires.</param>
/// <param name="Parameters">Action-specific payload.</param>
/// <param name="ProfileIds">Replacement profile-attachment set.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applies to every profile.</param>
/// <param name="CategoryIds">Replacement category assignment set.</param>
public sealed record UpdateHotkeyDto(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    Guid[]? CategoryIds = null);
