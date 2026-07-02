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

    [Fact]
    public async Task BulkDeleteAsync_OnSuccess_ReturnsParsedDto()
    {
        var missingId = Guid.NewGuid();
        BulkDeleteResultDto dto = new(2, [missingId]);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<BulkDeleteResultDto> result =
            await ClientWith(handler).BulkDeleteAsync([Guid.NewGuid(), Guid.NewGuid()]);

        result.IsSuccess.Should().BeTrue();
        result.Value!.DeletedCount.Should().Be(2);
        result.Value.MissingIds.Should().ContainSingle().Which.Should().Be(missingId);
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotkeys/bulk-delete");
    }

    [Fact]
    public async Task BulkDeleteAsync_OnValidation_ReturnsValidationResult()
    {
        var problem = new ApiProblemDetails(null, "Validation failed", 400, "Validation errors occurred.", null, null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.BadRequest, problem);

        ApiResult<BulkDeleteResultDto> result = await ClientWith(handler).BulkDeleteAsync([]);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Validation);
    }

    [Fact]
    public async Task GetHistoryAsync_OnSuccess_ReturnsEntries()
    {
        HistoryEntryDto[] entries = [new(1, HistoryChangeType.Edit, DateTimeOffset.UtcNow)];
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, entries);
        var id = Guid.NewGuid();

        ApiResult<HistoryEntryDto[]> result = await ClientWith(handler).GetHistoryAsync(id);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().ContainSingle();
        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotkeys/{id}/history");
    }

    [Fact]
    public async Task RevertAsync_PostsToRevertRoute()
    {
        HotkeyDto dto = new(
            Guid.NewGuid(),
            [],
            true,
            "Open Notepad",
            "n",
            true,
            false,
            false,
            false,
            HotkeyAction.Run,
            "notepad.exe",
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow,
            []);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotkeyDto> result = await ClientWith(handler).RevertAsync(dto.Id, 2);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotkeys/{dto.Id}/history/2/revert");
    }

    [Fact]
    public async Task ListDeletedAsync_GetsDeletedRoute()
    {
        DeletedHotkeyDto[] deleted =
            [new(Guid.NewGuid(), "Open Notepad", "n", true, false, false, false, DateTimeOffset.UtcNow)];
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, deleted);

        ApiResult<DeletedHotkeyDto[]> result = await ClientWith(handler).ListDeletedAsync();

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be("/api/v1/hotkeys/deleted");
    }

    [Fact]
    public async Task PurgeDeletedAsync_SendsDeleteToDeletedRoute()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);
        var id = Guid.NewGuid();

        ApiResult result = await ClientWith(handler).PurgeDeletedAsync(id);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Delete);
        handler.LastRequest.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotkeys/deleted/{id}");
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        private readonly HttpResponseMessage _response;
        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;
        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) =>
            new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });
        public static StubHttpMessageHandler StatusResponse(HttpStatusCode status) => new(new HttpResponseMessage(status));
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        { LastRequest = request; return Task.FromResult(_response); }
    }
}
