using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class ChangelogClientTests
{
    private static ChangelogClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task GetAsync_OnSuccess_DeserializesChangelog()
    {
        var dto = new ChangelogDocumentDto(
            1,
            [
                new ChangelogEntryDto(
                    "Unreleased",
                    Date: null,
                    IsUnreleased: true,
                    [
                        new ChangelogSectionDto("Added", ["In-app changelog"])
                    ])
            ]);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<ChangelogDocumentDto> result = await ClientWith(handler).GetAsync();

        result.IsSuccess.Should().BeTrue();
        result.Value!.SchemaVersion.Should().Be(1);
        result.Value.Entries.Should().ContainSingle();
        result.Value.Entries[0].Sections[0].Items.Should().Contain("In-app changelog");
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/changelog.json");
        handler.LastRequest.Method.Should().Be(HttpMethod.Get);
    }

    [Fact]
    public async Task GetAsync_OnNotFound_ReturnsNotFoundFailure()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NotFound);

        ApiResult<ChangelogDocumentDto> result = await ClientWith(handler).GetAsync();

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.NotFound);
    }

    [Fact]
    public async Task GetAsync_OnNetworkError_ReturnsNetworkFailure()
    {
        var handler = StubHttpMessageHandler.ThrowingHandler();

        ApiResult<ChangelogDocumentDto> result = await ClientWith(handler).GetAsync();

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
            if (_throw)
            {
                throw new HttpRequestException("Network error");
            }

            return Task.FromResult(_response);
        }
    }
}
