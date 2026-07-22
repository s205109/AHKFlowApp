namespace AHKFlowApp.Application.DTOs;

/// <summary>One canonical key the picker may offer, with the roles it may legally play.</summary>
/// <param name="Canonical">The single spelling persisted and emitted.</param>
/// <param name="Group">Picker grouping label.</param>
/// <param name="Roles">Role names — any of HotkeyKey, ComboPrefix, SendToken, RemapSource, RemapDest.</param>
/// <param name="RequiresBracesInSend">True for named keys, which AHK requires be braced inside Send.</param>
public sealed record HotkeyKeyDto(
    string Canonical,
    string Group,
    string[] Roles,
    bool RequiresBracesInSend);

/// <summary>The whole key registry plus its accepted alias spellings.</summary>
/// <param name="Keys">Every canonical key, in registry order.</param>
/// <param name="Aliases">Accepted non-canonical spellings mapped to the canonical name they resolve to.</param>
public sealed record HotkeyKeyCatalogDto(
    IReadOnlyList<HotkeyKeyDto> Keys,
    IReadOnlyDictionary<string, string> Aliases);
