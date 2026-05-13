using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IDashboardApiClient
{
    Task<ApiResult<DashboardStatsDto>> GetStatsAsync(CancellationToken ct = default);
}
