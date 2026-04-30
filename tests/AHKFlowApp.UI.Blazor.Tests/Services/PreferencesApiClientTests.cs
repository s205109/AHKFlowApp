using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class PreferencesApiClientTests
{
    private static PreferencesApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task GetAsync_OnSuccess_ReturnsPreferences()
    {
        var dto = new UserPreferenceDto(RowsPerPage: 25, DarkMode: true);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<UserPreferenceDto> result = await ClientWith(handler).GetAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.RowsPerPage.Should().Be(25);
        result.Value.DarkMode.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Get);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/preferences");
    }

    [Fact]
    public async Task GetAsync_On404_ReturnsNotFoundResult()
    {
        var problem = new ApiProblemDetails(null, "Not Found", 404, null, null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, problem);

        ApiResult<UserPreferenceDto> result = await ClientWith(handler).GetAsync();

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    [Fact]
    public async Task UpdateAsync_OnSuccess_SendsPutWithBody()
    {
        var dto = new UserPreferenceDto(RowsPerPage: 50, DarkMode: false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<UserPreferenceDto> result = await ClientWith(handler)
            .UpdateAsync(new UpdateUserPreferenceDto(50, false));

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Put);
        handler.LastRequest.RequestUri!.PathAndQuery.Should().Be("/api/v1/preferences");
        handler.LastRequest.Content.Should().NotBeNull();
    }

    [Fact]
    public async Task UpdateAsync_OnValidationFailure_ReturnsValidationStatus()
    {
        var problem = new ApiProblemDetails(null, "Bad Request", 400, "Invalid value", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.BadRequest, problem);

        ApiResult<UserPreferenceDto> result = await ClientWith(handler)
            .UpdateAsync(new UpdateUserPreferenceDto(7, false));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Validation);
        result.Problem!.Detail.Should().Contain("Invalid");
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;
        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            return Task.FromResult(_response);
        }
    }
}
