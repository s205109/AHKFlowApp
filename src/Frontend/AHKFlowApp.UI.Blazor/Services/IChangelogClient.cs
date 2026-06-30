using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IChangelogClient
{
    Task<ApiResult<ChangelogDocumentDto>> GetAsync(CancellationToken ct = default);
}
