using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class ProfilesApiClientTests
{
    private static ProfilesApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task ListAsync_OnSuccess_ReturnsProfileList()
    {
        var profiles = new List<ProfileDto>
        {
            new(Guid.NewGuid(), "Work", false, "header", "footer", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow),
        };
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, profiles);

        ApiResult<IReadOnlyList<ProfileDto>> result = await ClientWith(handler).ListAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/profiles");
    }

    [Fact]
    public async Task CreateAsync_OnSuccess_DeserializesResponseDto()
    {
        var created = new ProfileDto(Guid.NewGuid(), "Work", false, "header", "footer", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Created, created);

        ApiResult<ProfileDto> result = await ClientWith(handler).CreateAsync(new CreateProfileDto("Work"));

        result.IsSuccess.Should().BeTrue();
        result.Value!.Name.Should().Be("Work");
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/profiles");
    }

    [Fact]
    public async Task UpdateAsync_OnSuccess_DeserializesResponseDto()
    {
        var id = Guid.NewGuid();
        var updated = new ProfileDto(id, "Updated", true, "h", "f", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, updated);

        ApiResult<ProfileDto> result = await ClientWith(handler).UpdateAsync(id, new UpdateProfileDto("Updated", "h", "f", true));

        result.IsSuccess.Should().BeTrue();
        result.Value!.Name.Should().Be("Updated");
        handler.LastRequest!.Method.Should().Be(HttpMethod.Put);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be($"/api/v1/profiles/{id}");
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
        var problem = new ApiProblemDetails(null, "Not Found", 404, "Profile not found", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, problem);

        ApiResult result = await ClientWith(handler).DeleteAsync(Guid.NewGuid());

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
        result.Problem!.Detail.Should().Contain("not found");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Profile name already exists", "/api/v1/profiles", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        ApiResult<ProfileDto> result = await ClientWith(handler).CreateAsync(new CreateProfileDto("Work"));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task ListAsync_OnNetworkError_ReturnsNetworkErrorResult()
    {
        var handler = StubHttpMessageHandler.ThrowingHandler();

        ApiResult<IReadOnlyList<ProfileDto>> result = await ClientWith(handler).ListAsync();

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NetworkError);
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private readonly bool _throw;

        private StubHttpMessageHandler(HttpResponseMessage response, bool @throw = false)
        {
            _response = response;
            _throw = @throw;
        }

        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });

        public static StubHttpMessageHandler StatusResponse(HttpStatusCode status) =>
            new(new HttpResponseMessage(status));

        public static StubHttpMessageHandler ThrowingHandler() =>
            new(new HttpResponseMessage(HttpStatusCode.OK), @throw: true);

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            if (_throw) throw new HttpRequestException("Network error");
            return Task.FromResult(_response);
        }
    }
}
