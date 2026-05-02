using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotkeysApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IHotkeysApiClient
{
    private const string BasePath = "api/v1/hotkeys";

    public Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(Guid? profileId, int page, int pageSize, string? search = null, bool ignoreCase = true, CancellationToken ct = default)
    {
        string query = $"?page={page}&pageSize={pageSize}";
        if (profileId is { } pid) query += $"&profileId={pid}";
        if (!string.IsNullOrWhiteSpace(search)) query += $"&search={Uri.EscapeDataString(search)}";
        if (!ignoreCase) query += "&ignoreCase=false";
        return SendAsync<PagedList<HotkeyDto>>(HttpMethod.Get, BasePath + query, content: null, ct);
    }

    public Task<ApiResult<HotkeyDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotkeyDto>> CreateAsync(CreateHotkeyDto input, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotkeyDto>> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);
}
