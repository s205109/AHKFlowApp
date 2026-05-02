namespace AHKFlowApp.UI.Blazor.DTOs;

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
