namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>One canonical key the picker may offer. Mirror of the backend DTO.</summary>
public sealed record HotkeyKeyDto(
    string Canonical,
    string Group,
    string[] Roles,
    bool RequiresBracesInSend);

/// <summary>The key registry plus its accepted alias spellings. Mirror of the backend DTO.</summary>
public sealed record HotkeyKeyCatalogDto(
    IReadOnlyList<HotkeyKeyDto> Keys,
    IReadOnlyDictionary<string, string> Aliases);
