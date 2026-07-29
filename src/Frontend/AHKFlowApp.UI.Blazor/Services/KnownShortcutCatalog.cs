using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <inheritdoc cref="IKnownShortcutCatalog"/>
public sealed class KnownShortcutCatalog(IKnownShortcutsApiClient api) : IKnownShortcutCatalog
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private KnownShortcutCatalogDto? _catalog;

    public async ValueTask<KnownShortcutCatalogDto?> GetAsync(CancellationToken ct = default)
    {
        // Fast path, no gate: _catalog is written once and never mutated, and WASM's single
        // thread cannot tear the read.
        if (_catalog is not null)
            return _catalog;

        await _gate.WaitAsync(ct);
        try
        {
            // Re-check under the gate: another awaiter may have loaded it while we waited.
            if (_catalog is not null)
                return _catalog;

            ApiResult<KnownShortcutCatalogDto> result = await api.ListAsync(ct);

            // Assign only on success. Caching a failure would silence every warning for the rest
            // of the session, even after the server recovers — the trap HotkeyKeyCatalog
            // documents on EnsureCatalogAsync. Leaving _catalog null makes the next dialog open
            // retry.
            if (result.IsSuccess)
                _catalog = result.Value;

            return _catalog;
        }
        finally
        {
            _gate.Release();
        }
    }
}
