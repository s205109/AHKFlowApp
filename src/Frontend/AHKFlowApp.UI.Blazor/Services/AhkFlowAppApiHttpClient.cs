using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class AhkFlowAppApiHttpClient(HttpClient httpClient) : IAhkFlowAppApiHttpClient
{
    public async Task<HealthResponse?> GetHealthAsync(CancellationToken cancellationToken = default)
    {
        return await httpClient.GetFromJsonAsync<HealthResponse>(
            "api/v1/health",
            cancellationToken);
    }
}
