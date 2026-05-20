using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class CategoriesApiClientTests
{
    private static CategoriesApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    private static CategoryDto SampleDto() =>
        new(Guid.NewGuid(), "Work", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);

    [Fact]
    public async Task ListAsync_BuildsCorrectQueryString()
    {
        var paged = new PagedList<CategoryDto>([], 2, 10, 0, 0, false, true);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(new CategoryListRequest("email", Page: 2, PageSize: 10));

        handler.LastRequest!.RequestUri!.PathAndQuery
            .Should().Be("/api/v1/categories?page=2&pageSize=10&search=email");
    }

    [Fact]
    public async Task GetAsync_HitsCorrectUrl()
    {
        var id = Guid.NewGuid();
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, SampleDto());

        await ClientWith(handler).GetAsync(id);

        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be($"/api/v1/categories/{id}");
    }

    [Fact]
    public async Task CreateAsync_OnSuccess_DeserializesResponseDto()
    {
        CategoryDto dto = SampleDto();
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Created, dto);

        ApiResult<CategoryDto> result = await ClientWith(handler).CreateAsync(new CreateCategoryDto("Work"));

        result.IsSuccess.Should().BeTrue();
        result.Value!.Name.Should().Be(dto.Name);
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/categories");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResult()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Category already exists", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        ApiResult<CategoryDto> result = await ClientWith(handler).CreateAsync(new CreateCategoryDto("Work"));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task UpdateAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var problem = new ApiProblemDetails(null, "Not Found", 404, "Category not found", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, problem);

        ApiResult<CategoryDto> result = await ClientWith(handler).UpdateAsync(Guid.NewGuid(), new UpdateCategoryDto("X"));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    [Fact]
    public async Task DeleteAsync_On204_ReturnsSuccess()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);

        ApiResult result = await ClientWith(handler).DeleteAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Delete);
    }

    [Fact]
    public async Task DeleteAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var problem = new ApiProblemDetails(null, "Not Found", 404, "Category not found", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, problem);

        ApiResult result = await ClientWith(handler).DeleteAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;

        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;

        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });

        public static StubHttpMessageHandler StatusResponse(HttpStatusCode status) =>
            new(new HttpResponseMessage(status));

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            return Task.FromResult(_response);
        }
    }
}
