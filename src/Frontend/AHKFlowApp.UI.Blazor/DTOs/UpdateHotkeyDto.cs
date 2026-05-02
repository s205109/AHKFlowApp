namespace AHKFlowApp.UI.Blazor.DTOs;

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
