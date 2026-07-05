using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotstringsApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IHotstringsApiClient
{
    private const string BasePath = "api/v1/hotstrings";

    public Task<ApiResult<PagedList<HotstringDto>>> ListAsync(HotstringListRequest request, CancellationToken ct = default)
    {
        var parts = new List<string>
        {
            $"page={request.Page}",
            $"pageSize={request.PageSize}",
            $"sortDescending={request.SortDescending.ToString().ToLowerInvariant()}"
        };
        Add(parts, "profileId", request.ProfileId?.ToString());
        Add(parts, "search", request.Search);
        Add(parts, "sortField", request.SortField);
        Add(parts, "triggerFilter", request.TriggerFilter);
        Add(parts, "replacementFilter", request.ReplacementFilter);
        Add(parts, "descriptionFilter", request.DescriptionFilter);
        if (request.AppliesToAllProfiles.HasValue)
            parts.Add($"appliesToAllProfiles={request.AppliesToAllProfiles.Value.ToString().ToLowerInvariant()}");
        if (request.IsEndingCharacterRequired.HasValue)
            parts.Add($"isEndingCharacterRequired={request.IsEndingCharacterRequired.Value.ToString().ToLowerInvariant()}");
        if (request.IsTriggerInsideWord.HasValue)
            parts.Add($"isTriggerInsideWord={request.IsTriggerInsideWord.Value.ToString().ToLowerInvariant()}");
        if (request.CategoryIds is { Count: > 0 })
        {
            foreach (Guid id in request.CategoryIds)
                parts.Add($"categoryIds={id}");
        }
        return SendAsync<PagedList<HotstringDto>>(HttpMethod.Get, $"{BasePath}?{string.Join("&", parts)}", content: null, ct);
    }

    public Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);

    public Task<ApiResult<BulkDeleteResultDto>> BulkDeleteAsync(
        IReadOnlyList<Guid> ids,
        CancellationToken ct = default) =>
        SendAsync<BulkDeleteResultDto>(
            HttpMethod.Post,
            $"{BasePath}/bulk-delete",
            JsonContent.Create(new { ids }),
            ct);

    public Task<ApiResult<HistoryEntryDto[]>> GetHistoryAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HistoryEntryDto[]>(HttpMethod.Get, $"{BasePath}/{id}/history", content: null, ct);

    public Task<ApiResult<HotstringHistoryVersionDto>> GetHistoryVersionAsync(
        Guid id,
        int version,
        CancellationToken ct = default) =>
        SendAsync<HotstringHistoryVersionDto>(HttpMethod.Get, $"{BasePath}/{id}/history/{version}", content: null, ct);

    public Task<ApiResult<HotstringDto>> RevertAsync(Guid id, int version, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, $"{BasePath}/{id}/history/{version}/revert", content: null, ct);

    public Task<ApiResult<DeletedHotstringDto[]>> ListDeletedAsync(CancellationToken ct = default) =>
        SendAsync<DeletedHotstringDto[]>(HttpMethod.Get, $"{BasePath}/deleted", content: null, ct);

    public Task<ApiResult<HotstringDto>> RestoreAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, $"{BasePath}/{id}/restore", content: null, ct);

    public Task<ApiResult> PurgeDeletedAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/deleted/{id}", ct);

    public Task<ApiResult<HotstringImportPreviewDto>> PreviewImportAsync(string script, CancellationToken ct = default) =>
        SendAsync<HotstringImportPreviewDto>(
            HttpMethod.Post,
            $"{BasePath}/import/preview",
            JsonContent.Create(new { script }),
            ct);

    public Task<ApiResult<HotstringImportResultDto>> ImportAsync(ImportHotstringsRequestDto request, CancellationToken ct = default) =>
        SendAsync<HotstringImportResultDto>(
            HttpMethod.Post,
            $"{BasePath}/import",
            JsonContent.Create(request),
            ct);

    private static void Add(List<string> parts, string key, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value)) parts.Add($"{key}={Uri.EscapeDataString(value)}");
    }
}
