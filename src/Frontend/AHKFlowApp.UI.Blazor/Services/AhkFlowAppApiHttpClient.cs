using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class AhkFlowAppApiHttpClient(HttpClient httpClient) : IAhkFlowAppApiHttpClient
{
    public async Task<HealthResponse?> GetHealthAsync(CancellationToken cancellationToken = default)
    {
        using HttpResponseMessage response = await httpClient.GetAsync("api/v1/health", cancellationToken);

        // Health endpoint returns JSON for both 200 (Healthy/Degraded) and 503 (Unhealthy).
        if (response.StatusCode is HttpStatusCode.OK or HttpStatusCode.ServiceUnavailable)
        {
            return await response.Content.ReadFromJsonAsync<HealthResponse>(cancellationToken);
        }

        response.EnsureSuccessStatusCode();
        return null;
    }
}
