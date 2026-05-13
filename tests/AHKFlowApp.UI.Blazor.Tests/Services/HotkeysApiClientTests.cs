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

        ApiResult<PagedList<HotkeyDto>> result = await ClientWith(handler).ListAsync(new HotkeyListRequest());

        result.IsSuccess.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.Query.Should().Contain("page=1");
        handler.LastRequest.RequestUri.Query.Should().Contain("pageSize=50");
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

        await ClientWith(handler).ListAsync(new HotkeyListRequest(ProfileId: profileId));

        handler.LastRequest!.RequestUri!.Query.Should().Contain($"profileId={profileId}");
    }

    [Fact]
    public async Task ListAsync_WithGridParameters_AppendsEncodedQueryString()
    {
        var paged = new PagedList<HotkeyDto>([], 2, 25, 0, 0, false, false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(new HotkeyListRequest(
            Page: 2, PageSize: 25, SortField: "key", SortDescending: false,
            DescriptionFilter: "Open browser", Ctrl: true, Action: HotkeyAction.Run));

        string query = handler.LastRequest!.RequestUri!.Query;
        query.Should().Contain("page=2");
        query.Should().Contain("pageSize=25");
        query.Should().Contain("sortField=key");
        query.Should().Contain("sortDescending=false");
        query.Should().Contain("descriptionFilter=Open%20browser");
        query.Should().Contain("ctrl=true");
        query.Should().Contain("action=Run");
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
