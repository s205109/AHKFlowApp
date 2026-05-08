namespace AHKFlowApp.UI.Blazor.Services;

public interface IDownloadsApiClient
{
    Task<ApiResult<FileDownload>> GetProfileScriptAsync(Guid profileId, CancellationToken ct = default);
    Task<ApiResult<FileDownload>> GetAllProfileScriptsZipAsync(CancellationToken ct = default);
}
