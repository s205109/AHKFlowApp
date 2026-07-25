using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>
/// Session cache over the server's canonical key registry, plus the key-validity check the
/// grid uses to decide inline-edit eligibility.
/// </summary>
public interface IHotkeyKeyCatalog
{
    /// <summary>
    /// Keys legal in the given role, ordered by picker group then name, fetching the registry
    /// on first call. The ordering is what makes groups cluster in the picker's dropdown —
    /// MudAutocomplete 9.3.0 has no group-header support, so order plus a per-item group label
    /// is how grouping is conveyed.
    /// </summary>
    ValueTask<IReadOnlyList<HotkeyKeyDto>> ForRoleAsync(string role, CancellationToken ct = default);

    /// <summary>
    /// Whether a stored key would pass server-side key validation. Optimistic before the
    /// registry loads — a row must never be demoted to the dialog merely because the catalog
    /// has not arrived yet.
    /// </summary>
    bool IsValidKey(string? key);

    /// <summary>Picker group for a canonical registry name, or null for a vk/sc code or unknown name.</summary>
    string? GroupOf(string? canonical);

    /// <summary>
    /// Whether this key must be braced inside a Send token. True for named registry entries
    /// ({Volume_Up}) and for vk/sc codes ({vk1B}); false for a single printable character (c).
    /// Not meaningful for a remap destination, which is never braced.
    /// </summary>
    bool RequiresBracesInSend(string? canonical);
}
