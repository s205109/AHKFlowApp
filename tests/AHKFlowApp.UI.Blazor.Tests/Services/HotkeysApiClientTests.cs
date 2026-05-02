using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotkeysApiClientTests
{
    private static HotkeysApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task ListAsync_OnSuccess_ReturnsPagedList()
    {
        var paged = new PagedList<HotkeyDto>(
            Items: [new HotkeyDto(Guid.NewGuid(), [], true, "Open Notepad", "n", true, false, false, false,
                HotkeyAction.Run, "notepad.exe", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)],
            Page: 1, PageSize: 50, TotalCount: 1, TotalPages: 1, HasNextPage: false, HasPreviousPage: false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        ApiResult<PagedList<HotkeyDto>> result = await ClientWith(handler).ListAsync(profileId: null, page: 1, pageSize: 50);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.PathAndQuery.Should().Be("/api/v1/hotkeys?page=1&pageSize=50");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Modifier combo already exists", "/api/v1/hotkeys", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        var dto = new CreateHotkeyDto("Open Notepad", "n", Ctrl: true);
        ApiResult<HotkeyDto> result = await ClientWith(handler).CreateAsync(dto);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task ListAsync_WithProfileId_AppendsProfileIdToQueryString()
    {
        var profileId = Guid.NewGuid();
        var paged = new PagedList<HotkeyDto>([], 1, 50, 0, 0, false, false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(profileId: profileId, page: 1, pageSize: 50);

        handler.LastRequest!.RequestUri!.Query.Should().Contain($"profileId={profileId}");
    }

    [Fact]
    public async Task DeleteAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound,
            new ApiProblemDetails(null, "Not Found", 404, null, null, null));

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
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        { LastRequest = request; return Task.FromResult(_response); }
    }
}
