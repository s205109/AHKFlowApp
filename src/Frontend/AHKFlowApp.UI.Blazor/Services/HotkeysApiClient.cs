using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotkeysApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IHotkeysApiClient
{
    private const string BasePath = "api/v1/hotkeys";

    public Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(HotkeyListRequest request, CancellationToken ct = default)
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
        Add(parts, "descriptionFilter", request.DescriptionFilter);
        Add(parts, "keyFilter", request.KeyFilter);
        Add(parts, "parametersFilter", request.ParametersFilter);
        if (request.Action.HasValue)
            parts.Add($"action={Uri.EscapeDataString(request.Action.Value.ToString())}");
        if (request.AppliesToAllProfiles.HasValue)
            parts.Add($"appliesToAllProfiles={request.AppliesToAllProfiles.Value.ToString().ToLowerInvariant()}");
        if (request.Ctrl.HasValue)
            parts.Add($"ctrl={request.Ctrl.Value.ToString().ToLowerInvariant()}");
        if (request.Alt.HasValue)
            parts.Add($"alt={request.Alt.Value.ToString().ToLowerInvariant()}");
        if (request.Shift.HasValue)
            parts.Add($"shift={request.Shift.Value.ToString().ToLowerInvariant()}");
        if (request.Win.HasValue)
            parts.Add($"win={request.Win.Value.ToString().ToLowerInvariant()}");
        return SendAsync<PagedList<HotkeyDto>>(HttpMethod.Get, $"{BasePath}?{string.Join("&", parts)}", content: null, ct);
    }

    public Task<ApiResult<HotkeyDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotkeyDto>> CreateAsync(CreateHotkeyDto input, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotkeyDto>> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct = default) =>
        SendAsync<HotkeyDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);

    private static void Add(List<string> parts, string key, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value)) parts.Add($"{key}={Uri.EscapeDataString(value)}");
    }
}
