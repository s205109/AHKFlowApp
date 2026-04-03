using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IAhkFlowAppApiHttpClient
{
    Task<HealthResponse?> GetHealthAsync(CancellationToken cancellationToken = default);
}
