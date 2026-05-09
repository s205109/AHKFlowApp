namespace AHKFlowApp.CLI.Services;

public interface IDownloadsApiClient
{
    Task<DownloadResult> GetProfileScriptAsync(Guid profileId, CancellationToken ct);
    Task<DownloadResult> GetAllProfileScriptsZipAsync(CancellationToken ct);
}

public sealed record DownloadResult(byte[] Bytes, string FileName, string ContentType);
