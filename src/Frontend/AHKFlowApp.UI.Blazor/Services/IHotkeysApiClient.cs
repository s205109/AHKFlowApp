using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IHotkeysApiClient
{
    Task<ApiResult<PagedList<HotkeyDto>>> ListAsync(HotkeyListRequest request, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> CreateAsync(CreateHotkeyDto input, CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> UpdateAsync(Guid id, UpdateHotkeyDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<BulkDeleteResultDto>> BulkDeleteAsync(IReadOnlyList<Guid> ids, CancellationToken ct = default);
    Task<ApiResult<HistoryEntryDto[]>> GetHistoryAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotkeyHistoryVersionDto>> GetHistoryVersionAsync(
        Guid id,
        int version,
        CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> RevertAsync(Guid id, int version, CancellationToken ct = default);
    Task<ApiResult<DeletedHotkeyDto[]>> ListDeletedAsync(CancellationToken ct = default);
    Task<ApiResult<HotkeyDto>> RestoreAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult> PurgeDeletedAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotkeyKeyCatalogDto>> GetKeysAsync(CancellationToken ct = default);
    Task<ApiResult<HotkeyPreviewDto>> PreviewAsync(HotkeyPreviewRequestDto request, CancellationToken ct = default);
}
