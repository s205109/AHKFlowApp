using System.Net.Http.Headers;

namespace AHKFlowApp.CLI.Services;

public sealed class DownloadsApiClient(HttpClient http) : IDownloadsApiClient
{
    private const string DefaultProfileFileName = "profile.ahk";
    private const string DefaultZipFileName = "ahkflow_scripts.zip";
    private const string DefaultProfileContentType = "text/plain";
    private const string DefaultZipContentType = "application/zip";

    public async Task<DownloadResult> GetProfileScriptAsync(Guid profileId, CancellationToken ct)
    {
        using HttpResponseMessage response = await http.GetAsync($"api/v1/downloads/{profileId}", ct);
        return await ReadAsync(response, DefaultProfileFileName, DefaultProfileContentType, ct);
    }

    public async Task<DownloadResult> GetAllProfileScriptsZipAsync(CancellationToken ct)
    {
        using HttpResponseMessage response = await http.GetAsync("api/v1/downloads/zip", ct);
        return await ReadAsync(response, DefaultZipFileName, DefaultZipContentType, ct);
    }

    private static async Task<DownloadResult> ReadAsync(
        HttpResponseMessage response, string fallbackName, string fallbackContentType, CancellationToken ct)
    {
        if (!response.IsSuccessStatusCode)
        {
            string body = await response.Content.ReadAsStringAsync(ct);
            throw new ApiException((int)response.StatusCode, body);
        }

        byte[] bytes = await response.Content.ReadAsByteArrayAsync(ct);
        string raw = ExtractFileName(response.Content.Headers.ContentDisposition);
        string fileName = SafeFileName(raw, fallbackName);
        string contentType = response.Content.Headers.ContentType?.ToString() ?? fallbackContentType;
        return new DownloadResult(bytes, fileName, contentType);
    }

    private static string ExtractFileName(ContentDispositionHeaderValue? cd)
    {
        if (cd is null) return string.Empty;
        string? candidate = cd.FileNameStar ?? cd.FileName;
        if (string.IsNullOrWhiteSpace(candidate)) return string.Empty;
        return candidate.Trim().Trim('"');
    }

    private static string SafeFileName(string raw, string fallback)
    {
        if (string.IsNullOrWhiteSpace(raw)) return fallback;
        if (raw.Contains('/') || raw.Contains('\\')) return fallback;
        if (Path.IsPathRooted(raw)) return fallback;
        if (raw.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return fallback;
        if (Path.GetFileName(raw) != raw) return fallback;
        return raw;
    }
}
