using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IHotkeysApiClient
{
    Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(Guid? profileId, int page, int pageSize, string? search = null, bool ignoreCase = true, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> CreateAsync(CreateHotkeyDto input, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
