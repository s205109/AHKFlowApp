using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <inheritdoc cref="IKnownShortcutsApiClient"/>
public sealed class KnownShortcutsApiClient(HttpClient httpClient)
    : ApiClientBase(httpClient), IKnownShortcutsApiClient
{
    // Stage 1 serves the list from the hotkeys controller, beside the key registry.
    private const string ListPath = "api/v1/hotkeys/known-shortcuts";

    public Task<ApiResult<KnownShortcutCatalogDto>> ListAsync(CancellationToken ct = default) =>
        SendAsync<KnownShortcutCatalogDto>(HttpMethod.Get, ListPath, content: null, ct);
}
