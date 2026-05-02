using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IProfilesApiClient
{
    Task<ApiResult<IReadOnlyList<ProfileDto>>> ListAsync(CancellationToken ct = default);
    Task<ApiResult<ProfileDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<ProfileDto>> CreateAsync(CreateProfileDto input, CancellationToken ct = default);
    Task<ApiResult<ProfileDto>> UpdateAsync(Guid id, UpdateProfileDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
