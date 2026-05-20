using System.Net.Http.Json;
using System.Text;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class CategoriesApiClient(HttpClient httpClient) : ApiClientBase(httpClient), ICategoriesApiClient
{
    private const string BasePath = "api/v1/categories";

    public Task<ApiResult<PagedList<CategoryDto>>> ListAsync(CategoryListRequest request, CancellationToken ct = default)
    {
        StringBuilder qs = new("?");
        qs.Append("page=").Append(request.Page);
        qs.Append("&pageSize=").Append(request.PageSize);
        if (!string.IsNullOrWhiteSpace(request.Search))
            qs.Append("&search=").Append(Uri.EscapeDataString(request.Search));

        return SendAsync<PagedList<CategoryDto>>(HttpMethod.Get, $"{BasePath}{qs}", content: null, ct);
    }

    public Task<ApiResult<CategoryDto>> GetAsync(Guid id, CancellationToken ct = default) =>
        SendAsync<CategoryDto>(HttpMethod.Get, $"{BasePath}/{id}", content: null, ct);

    public Task<ApiResult<CategoryDto>> CreateAsync(CreateCategoryDto input, CancellationToken ct = default) =>
        SendAsync<CategoryDto>(HttpMethod.Post, BasePath, JsonContent.Create(input), ct);

    public Task<ApiResult<CategoryDto>> UpdateAsync(Guid id, UpdateCategoryDto input, CancellationToken ct = default) =>
        SendAsync<CategoryDto>(HttpMethod.Put, $"{BasePath}/{id}", JsonContent.Create(input), ct);

    public Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default) =>
        SendNoContentAsync(HttpMethod.Delete, $"{BasePath}/{id}", ct);
}
