using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IHotstringsApiClient
{
    Task<ApiResult<PagedList<HotstringDto>>> ListAsync(Guid? profileId, int page, int pageSize, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
