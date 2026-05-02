using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

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
    DateTimeOffset UpdatedAt);

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
    bool AppliesToAllProfiles = false);

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
    bool AppliesToAllProfiles);
