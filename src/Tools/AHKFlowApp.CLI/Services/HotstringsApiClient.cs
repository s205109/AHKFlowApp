using System.Net.Http.Json;
using System.Text.Json;

namespace AHKFlowApp.CLI.Services;

public sealed class HotstringsApiClient(HttpClient http) : IHotstringsApiClient
{
    private static readonly JsonSerializerOptions JsonOptions = JsonSerializerOptions.Web;

    public async Task<HotstringDto> CreateAsync(CreateHotstringDto input, CancellationToken ct)
    {
        using HttpResponseMessage response = await http.PostAsJsonAsync(
            "api/v1/hotstrings", input, JsonOptions, ct);
        if (!response.IsSuccessStatusCode)
        {
            string body = await response.Content.ReadAsStringAsync(ct);
            throw new ApiException((int)response.StatusCode, body, response.Content.Headers.ContentType?.MediaType);
        }
        HotstringDto dto = await response.Content.ReadFromJsonAsync<HotstringDto>(JsonOptions, ct)
            ?? throw new InvalidOperationException("API returned empty body for create hotstring.");
        return dto;
    }

    public async Task<PagedList<HotstringDto>> ListAsync(
        Guid? profileId, string? search, int page, int pageSize, CancellationToken ct)
    {
        List<string> qs = [];
        if (profileId is { } pid) qs.Add($"profileId={Uri.EscapeDataString(pid.ToString())}");
        if (!string.IsNullOrWhiteSpace(search)) qs.Add($"search={Uri.EscapeDataString(search)}");
        qs.Add($"page={page}");
        qs.Add($"pageSize={pageSize}");
        string url = $"api/v1/hotstrings?{string.Join('&', qs)}";

        using HttpResponseMessage response = await http.GetAsync(url, ct);
        if (!response.IsSuccessStatusCode)
        {
            string body = await response.Content.ReadAsStringAsync(ct);
            throw new ApiException((int)response.StatusCode, body, response.Content.Headers.ContentType?.MediaType);
        }
        PagedList<HotstringDto> result = await response.Content
            .ReadFromJsonAsync<PagedList<HotstringDto>>(JsonOptions, ct)
            ?? throw new InvalidOperationException("API returned empty body for list hotstrings.");
        return result;
    }
}
