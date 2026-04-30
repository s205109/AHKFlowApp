using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public abstract class ApiClientBase(HttpClient httpClient)
{
    protected async Task<ApiResult<T>> SendAsync<T>(HttpMethod method, string path, HttpContent? content, CancellationToken ct)
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

    protected async Task<ApiResult> SendNoContentAsync(HttpMethod method, string path, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(method, path);
            using HttpResponseMessage resp = await httpClient.SendAsync(req, ct);
            if (resp.StatusCode == HttpStatusCode.NoContent) return ApiResult.Ok();
            ApiProblemDetails? problem = await TryReadProblem(resp, ct);
            return ApiResult.Failure(MapStatus(resp.StatusCode), problem);
        }
        catch (HttpRequestException) { return ApiResult.Failure(ApiResultStatus.NetworkError, null); }
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
