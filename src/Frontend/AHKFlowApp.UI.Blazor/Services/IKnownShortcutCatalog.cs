using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>
/// Session cache over the server's known-shortcut catalog. Mirrors <see cref="IHotkeyKeyCatalog"/>,
/// which caches the key registry the same way for the same reason.
/// </summary>
public interface IKnownShortcutCatalog
{
    /// <summary>
    /// The catalog, fetching it on first call and reusing it afterwards. Null when the fetch
    /// failed — the caller shows no warning, and the next call tries again.
    /// </summary>
    ValueTask<KnownShortcutCatalogDto?> GetAsync(CancellationToken ct = default);
}
