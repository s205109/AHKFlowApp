using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public interface ICategoriesApiClient
{
    Task<ApiResult<PagedList<CategoryDto>>> ListAsync(CategoryListRequest request, CancellationToken ct = default);
    Task<ApiResult<CategoryDto>> GetAsync(Guid id, CancellationToken ct = default);
    Task<ApiResult<CategoryDto>> CreateAsync(CreateCategoryDto input, CancellationToken ct = default);
    Task<ApiResult<CategoryDto>> UpdateAsync(Guid id, UpdateCategoryDto input, CancellationToken ct = default);
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);
}
