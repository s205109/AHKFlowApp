using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IPreferencesApiClient
{
    Task<ApiResult<UserPreferenceDto>> GetAsync(CancellationToken ct = default);
    Task<ApiResult<UserPreferenceDto>> UpdateAsync(UpdateUserPreferenceDto input, CancellationToken ct = default);
}
