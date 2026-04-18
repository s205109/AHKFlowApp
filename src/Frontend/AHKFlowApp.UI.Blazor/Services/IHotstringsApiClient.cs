using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public enum ApiResultStatus { Ok, Validation, NotFound, Conflict, Unauthorized, Forbidden, ServerError, NetworkError }

public sealed record ApiResult<T>(bool IsSuccess, ApiResultStatus Status, T? Value, ApiProblemDetails? Problem)
{
    public static ApiResult<T> Ok(T value) => new(true, ApiResultStatus.Ok, value, null);
    public static ApiResult<T> Failure(ApiResultStatus status, ApiProblemDetails? problem) => new(false, status, default, problem);
}

public sealed record ApiResult(bool IsSuccess, ApiResultStatus Status, ApiProblemDetails? Problem)
{
    public static ApiResult Ok() => new(true, ApiResultStatus.Ok, null);
    public static ApiResult Failure(ApiResultStatus status, ApiProblemDetails? problem) => new(false, status, problem);
}

public interface IHotstringsApiClient
{
    Task<ApiResult<PagedList<HotstringDto>>> ListAsync(Guid? profileId, int page, int pageSize, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> CreateAsync(CreateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult<HotstringDto>> UpdateAsync(Guid id, UpdateHotstringDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
