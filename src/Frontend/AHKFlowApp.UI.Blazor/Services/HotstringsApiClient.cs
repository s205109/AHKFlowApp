using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotstringsApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IHotstringsApiClient
{
    private const string BasePath = "api/v1/hotstrings";

    public Task<ApiResult<PagedList<HotstringDto>>> ListAsync(Guid? profileId, int page, int pageSize, string? search = null, bool ignoreCase = true, CancellationToken ct = default)
    {
        string query = $"?page={page}&pageSize={pageSize}";
        if (profileId is { } pid) query += $"&profileId={pid}";
        if (!string.IsNullOrWhiteSpace(search)) query += $"&search={Uri.EscapeDataString(search)}";
        if (!ignoreCase) query += "&ignoreCase=false";
        return SendAsync<PagedList<HotstringDto>>(HttpMethod.Get, BasePath + query, content: null, ct);
    }

    public Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);
}
