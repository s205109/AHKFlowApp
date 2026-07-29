using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <inheritdoc cref="IKnownShortcutsApiClient"/>
public sealed class KnownShortcutsApiClient(HttpClient httpClient)
    : ApiClientBase(httpClient), IKnownShortcutsApiClient
{
    // The dialog list is served from the hotkeys controller, beside the key registry.
    private const string DialogListPath = "api/v1/hotkeys/known-shortcuts";

    // The owner's own view of the list, and their edits to it, live on their own controller.
    private const string BasePath = "api/v1/knownshortcuts";

    public Task<ApiResult<KnownShortcutCatalogDto>> ListAsync(CancellationToken ct = default) =>
        SendAsync<KnownShortcutCatalogDto>(HttpMethod.Get, DialogListPath, content: null, ct);

    public Task<ApiResult<ManagedKnownShortcutCatalogDto>> ListManagedAsync(CancellationToken ct = default) =>
        SendAsync<ManagedKnownShortcutCatalogDto>(HttpMethod.Get, BasePath, content: null, ct);

    public Task<ApiResult<ManagedKnownShortcutCatalogDto>> CreateAsync(
        CreateCustomKnownShortcutDto input, CancellationToken ct = default) =>
        SendAsync<ManagedKnownShortcutCatalogDto>(
            HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);

    public Task<ApiResult> IgnoreAsync(string shortcutId, string usedBy, CancellationToken ct = default) =>
        SendNoContentAsync(
            HttpMethod.Post,
            $"{BasePath}/ignore",
            JsonContent.Create(new KnownShortcutUseRefDto(shortcutId, usedBy)),
            ct);

    public Task<ApiResult> RestoreAsync(string shortcutId, string usedBy, CancellationToken ct = default) =>
        SendNoContentAsync(
            HttpMethod.Post,
            $"{BasePath}/restore",
            JsonContent.Create(new KnownShortcutUseRefDto(shortcutId, usedBy)),
            ct);
}
