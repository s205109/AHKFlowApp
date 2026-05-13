using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class DashboardApiClientTests
{
    private static DashboardApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task GetStatsAsync_OnSuccess_DeserializesDto()
    {
        var dto = new DashboardStatsDto(
            new EntityStatsDto(15, 3, Enumerable.Repeat(1, 14).ToArray()),
            new EntityStatsDto(6, 1, Enumerable.Repeat(0, 14).ToArray()),
            new ProfileStatsDto(5, 2, 1, Enumerable.Repeat(0, 14).ToArray()),
            Array.Empty<RecentActivityItemDto>());
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<DashboardStatsDto> result = await ClientWith(handler).GetStatsAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.Hotstrings.Total.Should().Be(15);
        result.Value.Profiles.Default.Should().Be(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/dashboard/stats");
        handler.LastRequest.Method.Should().Be(HttpMethod.Get);
    }

    [Fact]
    public async Task GetStatsAsync_On500_ReturnsFailure()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.InternalServerError);

        ApiResult<DashboardStatsDto> result = await ClientWith(handler).GetStatsAsync();

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.ServerError);
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
