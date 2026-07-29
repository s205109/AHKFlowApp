using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <inheritdoc cref="IKnownShortcutCatalog"/>
public sealed class KnownShortcutCatalog(IKnownShortcutsApiClient api) : IKnownShortcutCatalog
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private KnownShortcutCatalogDto? _catalog;

    // Bumped by Invalidate. A fetch that started before the bump must not write its result back:
    // it read the server before the mutation, so caching it would undo the invalidation.
    private int _generation;

    public void Invalidate()
    {
        _catalog = null;
        _generation++;
    }

    public async ValueTask<KnownShortcutCatalogDto?> GetAsync(CancellationToken ct = default)
    {
        // Fast path, no gate: the field holds a whole immutable catalog, and WASM's single thread
        // cannot tear the read. Invalidate only ever replaces the reference with null.
        if (_catalog is not null)
            return _catalog;

        await _gate.WaitAsync(ct);
        try
        {
            // Re-check under the gate: another awaiter may have loaded it while we waited.
            if (_catalog is not null)
                return _catalog;

            int generation = _generation;
            ApiResult<KnownShortcutCatalogDto> result = await api.ListAsync(ct);

            // Assign only on success. Caching a failure would silence every warning for the rest
            // of the session, even after the server recovers — the trap HotkeyKeyCatalog
            // documents on EnsureCatalogAsync. Leaving _catalog null makes the next dialog open
            // retry.
            // Assign only if nothing invalidated while the request was in flight, too. The caller
            // still gets this response — it is the freshest thing anyone has — it just does not
            // become the cached one.
            if (result.IsSuccess && generation == _generation)
                _catalog = result.Value;

            return result.IsSuccess ? result.Value : _catalog;
        }
        finally
        {
            _gate.Release();
        }
    }
}
