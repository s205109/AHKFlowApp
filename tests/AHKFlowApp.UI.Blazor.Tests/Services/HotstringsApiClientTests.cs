using System.Net;
using System.Net.Http.Json;
using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Services;

public sealed class HotstringsApiClientTests
{
    private static HotstringsApiClient ClientWith(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler) { BaseAddress = new Uri("http://localhost/") });

    [Fact]
    public async Task ListAsync_OnSuccess_ReturnsPagedList()
    {
        var paged = new PagedList<HotstringDto>(
            Items: [new HotstringDto(Guid.NewGuid(), [], true, "btw", "by the way", null, true, true, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow)],
            Page: 1, PageSize: 50, TotalCount: 1, TotalPages: 1, HasNextPage: false, HasPreviousPage: false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        ApiResult<PagedList<HotstringDto>> result = await ClientWith(handler).ListAsync(new HotstringListRequest());

        result.IsSuccess.Should().BeTrue();
        result.Value!.Items.Should().HaveCount(1);
        handler.LastRequest!.RequestUri!.Query.Should().Contain("page=1");
        handler.LastRequest.RequestUri.Query.Should().Contain("pageSize=50");
    }

    [Fact]
    public async Task CreateAsync_OnConflict_ReturnsConflictResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Conflict", 409, "Trigger already exists for profile", "/api/v1/hotstrings", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.Conflict, problem);

        ApiResult<HotstringDto> result = await ClientWith(handler).CreateAsync(new CreateHotstringDto("btw", "by the way"));

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Conflict);
        result.Problem!.Detail.Should().Contain("already exists");
    }

    [Fact]
    public async Task ListAsync_WithProfileId_AppendsProfileIdToQueryString()
    {
        var profileId = Guid.NewGuid();
        var paged = new PagedList<HotstringDto>([], 1, 50, 0, 0, false, false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(new HotstringListRequest(ProfileId: profileId));

        handler.LastRequest!.RequestUri!.Query.Should().Contain($"profileId={profileId}");
    }

    [Fact]
    public async Task ListAsync_WithGridParameters_AppendsEncodedQueryString()
    {
        var paged = new PagedList<HotstringDto>([], 1, 25, 0, 0, false, false);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, paged);

        await ClientWith(handler).ListAsync(new HotstringListRequest(
            Page: 2, PageSize: 25, SortField: "trigger", SortDescending: false,
            TriggerFilter: "bt w", ReplacementFilter: null,
            AppliesToAllProfiles: true));

        string query = handler.LastRequest!.RequestUri!.Query;
        query.Should().Contain("page=2");
        query.Should().Contain("pageSize=25");
        query.Should().Contain("sortField=trigger");
        query.Should().Contain("sortDescending=false");
        query.Should().Contain("triggerFilter=bt%20w");
        query.Should().Contain("appliesToAllProfiles=true");
    }

    [Fact]
    public async Task DeleteAsync_OnNotFound_ReturnsNotFoundResult()
    {
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.NotFound, new ApiProblemDetails(null, "Not Found", 404, null, null, null));

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
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotstrings/bulk-delete");
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
        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotstrings/{id}/history");
    }

    [Fact]
    public async Task RevertAsync_PostsToRevertRoute()
    {
        HotstringDto dto = new(
            Guid.NewGuid(),
            [],
            true,
            "btw",
            "by the way",
            null,
            true,
            true,
            DateTimeOffset.UtcNow,
            DateTimeOffset.UtcNow,
            []);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotstringDto> result = await ClientWith(handler).RevertAsync(dto.Id, 2);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotstrings/{dto.Id}/history/2/revert");
    }

    [Fact]
    public async Task ListDeletedAsync_GetsDeletedRoute()
    {
        DeletedHotstringDto[] deleted = [new(Guid.NewGuid(), "btw", "by the way", null, DateTimeOffset.UtcNow)];
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, deleted);

        ApiResult<DeletedHotstringDto[]> result = await ClientWith(handler).ListDeletedAsync();

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.RequestUri!.AbsolutePath.Should().Be("/api/v1/hotstrings/deleted");
    }

    [Fact]
    public async Task PurgeDeletedAsync_SendsDeleteToDeletedRoute()
    {
        var handler = StubHttpMessageHandler.StatusResponse(HttpStatusCode.NoContent);
        var id = Guid.NewGuid();

        ApiResult result = await ClientWith(handler).PurgeDeletedAsync(id);

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Delete);
        handler.LastRequest.RequestUri!.AbsolutePath.Should().Be($"/api/v1/hotstrings/deleted/{id}");
    }

    [Fact]
    public async Task PreviewImportAsync_PostsScriptToPreviewRoute()
    {
        HotstringImportPreviewDto dto = new([], 0, 0, 0, 0);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotstringImportPreviewDto> result =
            await ClientWith(handler).PreviewImportAsync("::btw::by the way");

        result.IsSuccess.Should().BeTrue();
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotstrings/import/preview");
        handler.LastRequestBody.Should().Contain("::btw::by the way");
    }

    [Fact]
    public async Task ImportAsync_PostsRequestToImportRoute()
    {
        HotstringImportResultDto dto = new(1, 0, []);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);

        ApiResult<HotstringImportResultDto> result = await ClientWith(handler)
            .ImportAsync(new ImportHotstringsRequestDto("::btw::x", AppliesToAllProfiles: false, ProfileIds: [Guid.NewGuid()]));

        result.IsSuccess.Should().BeTrue();
        result.Value!.ImportedCount.Should().Be(1);
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotstrings/import");
    }

    [Fact]
    public async Task PreviewAsync_PostsRequestToPreviewRoute()
    {
        HotstringPreviewDto dto = new("::btw::by the way");
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.OK, dto);
        var request = new HotstringPreviewRequestDto(
            HotstringKind.Macro,
            "btw",
            "Dear {{cursor}}",
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: true);

        ApiResult<HotstringPreviewDto> result = await ClientWith(handler).PreviewAsync(request);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Snippet.Should().Be("::btw::by the way");
        handler.LastRequest!.Method.Should().Be(HttpMethod.Post);
        handler.LastRequest.RequestUri!.ToString().Should().Be("http://localhost/api/v1/hotstrings/preview");
        handler.LastRequestBody.Should().Contain("\"trigger\":\"btw\"");
        handler.LastRequestBody.Should().Contain("\"replacement\":\"Dear {{cursor}}\"");
        handler.LastRequestBody.Should().Contain("\"kind\":2");
    }

    [Fact]
    public async Task PreviewAsync_OnValidationError_ReturnsValidationResultWithProblemDetails()
    {
        var problem = new ApiProblemDetails(null, "Validation failed", 400, "Trigger is required.", "/api/v1/hotstrings/preview", null);
        var handler = StubHttpMessageHandler.JsonResponse(HttpStatusCode.BadRequest, problem);
        var request = new HotstringPreviewRequestDto(
            HotstringKind.Text,
            string.Empty,
            "by the way",
            IsCaseSensitive: false,
            OmitEndingCharacter: false,
            IsEndingCharacterRequired: true,
            IsTriggerInsideWord: true);

        ApiResult<HotstringPreviewDto> result = await ClientWith(handler).PreviewAsync(request);

        result.IsSuccess.Should().BeFalse();
        result.Status.Should().Be(ApiResultStatus.Validation);
        result.Problem!.Detail.Should().Contain("Trigger is required");
    }

    private sealed class StubHttpMessageHandler : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }
        public string? LastRequestBody { get; private set; }
        private readonly HttpResponseMessage _response;
        private StubHttpMessageHandler(HttpResponseMessage response) => _response = response;
        public static StubHttpMessageHandler JsonResponse<T>(HttpStatusCode status, T body) => new(new HttpResponseMessage(status) { Content = JsonContent.Create(body) });
        public static StubHttpMessageHandler StatusResponse(HttpStatusCode status) => new(new HttpResponseMessage(status));
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            LastRequest = request;
            LastRequestBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(ct);
            return _response;
        }
    }
}
