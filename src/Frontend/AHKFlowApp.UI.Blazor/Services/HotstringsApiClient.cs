using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class HotstringsApiClient(HttpClient httpClient) : IHotstringsApiClient
{
    private const string BasePath = "api/v1/hotstrings";

    public async Task<ApiResult<PagedList<HotstringDto>>> ListAsync(Guid? profileId, int page, int pageSize, CancellationToken ct = default)
    {
        string query = $"?page={page}&pageSize={pageSize}" + (profileId is { } pid ? $"&profileId={pid}" : "");
        return await SendAsync<PagedList<HotstringDto>>(HttpMethod.Get, BasePath + query, content: null, ct);
    }

    public Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default) =>
        SendAsync<HotstringDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public async Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Delete, $"{BasePath}/{id}");
            using HttpResponseMessage resp = await httpClient.SendAsync(req, ct);
            if (resp.StatusCode == HttpStatusCode.NoContent) return ApiResult.Ok();
            ApiProblemDetails? problem = await TryReadProblem(resp, ct);
            return ApiResult.Failure(MapStatus(resp.StatusCode), problem);
        }
        catch (HttpRequestException) { return ApiResult.Failure(ApiResultStatus.NetworkError, null); }
    }

    private async Task<ApiResult<T>> SendAsync<T>(HttpMethod method, string path, HttpContent? content, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(method, path) { Content = content };
            using HttpResponseMessage resp = await httpClient.SendAsync(req, ct);
            if (resp.IsSuccessStatusCode)
            {
                T? value = await resp.Content.ReadFromJsonAsync<T>(ct);
                return value is null ? ApiResult<T>.Failure(ApiResultStatus.ServerError, null) : ApiResult<T>.Ok(value);
            }
            ApiProblemDetails? problem = await TryReadProblem(resp, ct);
            return ApiResult<T>.Failure(MapStatus(resp.StatusCode), problem);
        }
        catch (HttpRequestException) { return ApiResult<T>.Failure(ApiResultStatus.NetworkError, null); }
    }

    private static async Task<ApiProblemDetails?> TryReadProblem(HttpResponseMessage resp, CancellationToken ct)
    {
        try { return await resp.Content.ReadFromJsonAsync<ApiProblemDetails>(ct); }
        catch (Exception ex) when (ex is JsonException or NotSupportedException or IOException) { return null; }
    }

    private static ApiResultStatus MapStatus(HttpStatusCode code) => code switch
    {
        HttpStatusCode.BadRequest or HttpStatusCode.UnprocessableEntity => ApiResultStatus.Validation,
        HttpStatusCode.NotFound => ApiResultStatus.NotFound,
        HttpStatusCode.Conflict => ApiResultStatus.Conflict,
        HttpStatusCode.Unauthorized => ApiResultStatus.Unauthorized,
        HttpStatusCode.Forbidden => ApiResultStatus.Forbidden,
        _ => ApiResultStatus.ServerError,
    };
}
