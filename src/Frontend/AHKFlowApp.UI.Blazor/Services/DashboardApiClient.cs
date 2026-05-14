using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class DashboardApiClient(HttpClient httpClient) : ApiClientBase(httpClient), IDashboardApiClient
{
    private const string Path = "api/v1/dashboard/stats";

    public Task<ApiResult<DashboardStatsDto>> GetStatsAsync(CancellationToken ct = default) =>
        SendAsync<DashboardStatsDto>(HttpMethod.Get, Path, content: null, ct);
}
