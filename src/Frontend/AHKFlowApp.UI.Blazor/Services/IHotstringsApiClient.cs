using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface IHotstringsApiClient
{
    Task<ApiResult<PagedList<HotstringDto>>> ListAsync(HotstringListRequest request, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<BulkDeleteResultDto>> BulkDeleteAsync(IReadOnlyList<Guid> ids, CancellationToken ct = default);
    Task<ApiResult<HistoryEntryDto[]>> GetHistoryAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotstringHistoryVersionDto>> GetHistoryVersionAsync(
        Guid id,
        int version,
        CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> RevertAsync(Guid id, int version, CancellationToken ct = default);
    Task<ApiResult<DeletedHotstringDto[]>> ListDeletedAsync(CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> RestoreAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult> PurgeDeletedAsync(Guid id, CancellationToken ct = default);
}
