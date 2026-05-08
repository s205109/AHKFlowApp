using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class DownloadsApiClient(HttpClient httpClient) : IDownloadsApiClient
{
    private const string BasePath = "api/v1/downloads";

    public Task<ApiResult<FileDownload>> GetProfileScriptAsync(Guid profileId, CancellationToken ct = default) =>
        GetFileAsync($"{BasePath}/{profileId}", "ahkflow_profile.ahk", ct);

    public Task<ApiResult<FileDownload>> GetAllProfileScriptsZipAsync(CancellationToken ct = default) =>
        GetFileAsync($"{BasePath}/zip", "ahkflow_scripts.zip", ct);

    private async Task<ApiResult<FileDownload>> GetFileAsync(string path, string fallbackFileName, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, path);
            using HttpResponseMessage resp = await httpClient.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
            {
                ApiProblemDetails? problem = await TryReadProblem(resp, ct);
                return ApiResult<FileDownload>.Failure(MapStatus(resp.StatusCode), problem);
            }

            byte[] bytes = await resp.Content.ReadAsByteArrayAsync(ct);
            string fileName = resp.Content.Headers.ContentDisposition?.FileName?.Trim('"') ?? fallbackFileName;
            string contentType = resp.Content.Headers.ContentType?.ToString() ?? "application/octet-stream";
            return ApiResult<FileDownload>.Ok(new FileDownload(bytes, fileName, contentType));
        }
        catch (HttpRequestException) { return ApiResult<FileDownload>.Failure(ApiResultStatus.NetworkError, null); }
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
