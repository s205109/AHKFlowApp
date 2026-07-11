using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status403Forbidden)]
public sealed class HotstringsController(
    IUseCase<ListHotstringsQuery, Result<PagedList<HotstringDto>>> listHotstrings,
    IUseCase<GetHotstringQuery, Result<HotstringDto>> getHotstring,
    IUseCase<CreateHotstringCommand, Result<HotstringDto>> createHotstring,
    IUseCase<BulkDeleteHotstringsCommand, Result<BulkDeleteResultDto>> bulkDeleteHotstrings,
    IUseCase<UpdateHotstringCommand, Result<HotstringDto>> updateHotstring,
    IUseCase<DeleteHotstringCommand, Result> deleteHotstring,
    IUseCase<GetHotstringHistoryQuery, Result<HistoryEntryDto[]>> getHotstringHistory,
    IUseCase<GetHotstringHistoryVersionQuery, Result<HotstringHistoryVersionDto>> getHotstringHistoryVersion,
    IUseCase<RevertHotstringCommand, Result<HotstringDto>> revertHotstring,
    IUseCase<ListDeletedHotstringsQuery, Result<DeletedHotstringDto[]>> listDeletedHotstrings,
    IUseCase<RestoreHotstringCommand, Result<HotstringDto>> restoreHotstring,
    IUseCase<PurgeDeletedHotstringCommand, Result> purgeDeletedHotstring,
    IUseCase<PreviewHotstringImportCommand, Result<HotstringImportPreviewDto>> previewImport,
    IUseCase<ImportHotstringsCommand, Result<HotstringImportResultDto>> importHotstrings,
    IUseCase<GetHotstringPreviewQuery, Result<HotstringPreviewDto>> previewHotstring) : ControllerBase
{
    /// <summary>List hotstrings for the current user, optionally filtered by profile. Paginated.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedList<HotstringDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedList<HotstringDto>>> List(
        [FromQuery] Guid? profileId,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string? sortField = null,
        [FromQuery] bool sortDescending = true,
        [FromQuery] string? triggerFilter = null,
        [FromQuery] string? replacementFilter = null,
        [FromQuery] string? descriptionFilter = null,
        [FromQuery] bool? appliesToAllProfiles = null,
        [FromQuery] bool? isEndingCharacterRequired = null,
        [FromQuery] bool? isTriggerInsideWord = null,
        [FromQuery] Guid[]? categoryIds = null,
        [FromQuery] HotstringKind? kind = null,
        CancellationToken ct = default) =>
        (await listHotstrings.ExecuteAsync(new ListHotstringsQuery(
            profileId,
            search,
            page,
            pageSize,
            sortField,
            sortDescending,
            triggerFilter,
            replacementFilter,
            descriptionFilter,
            appliesToAllProfiles,
            isEndingCharacterRequired,
            isTriggerInsideWord,
            categoryIds,
            kind), ct)).ToProblemActionResult(this);

    /// <summary>Get a hotstring by id.</summary>
    [HttpGet("{id:guid}", Name = "GetHotstring")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HotstringDto>> Get(Guid id, CancellationToken ct) =>
        (await getHotstring.ExecuteAsync(new GetHotstringQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Create a new hotstring for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Create([FromBody] CreateHotstringDto dto, CancellationToken ct)
    {
        Result<HotstringDto> result = await createHotstring.ExecuteAsync(new CreateHotstringCommand(dto), ct);

        return result.IsSuccess
            ? CreatedAtRoute("GetHotstring", new { id = result.Value.Id }, result.Value)
            : result.ToProblemActionResult(this);
    }

    /// <summary>Delete multiple hotstrings owned by the current user.</summary>
    [HttpPost("bulk-delete")]
    [ProducesResponseType(typeof(BulkDeleteResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<BulkDeleteResultDto>> BulkDelete(
        [FromBody] BulkDeleteRequestDto dto,
        CancellationToken ct) =>
        (await bulkDeleteHotstrings.ExecuteAsync(new BulkDeleteHotstringsCommand(dto), ct)).ToProblemActionResult(this);

    /// <summary>Update an existing hotstring. Returns the updated representation.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Update(Guid id, [FromBody] UpdateHotstringDto dto, CancellationToken ct) =>
        (await updateHotstring.ExecuteAsync(new UpdateHotstringCommand(id, dto), ct)).ToProblemActionResult(this);

    /// <summary>Delete a hotstring.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        Result result = await deleteHotstring.ExecuteAsync(new DeleteHotstringCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }

    /// <summary>List saved versions of a hotstring, newest first.</summary>
    [HttpGet("{id:guid}/history")]
    [ProducesResponseType(typeof(HistoryEntryDto[]), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HistoryEntryDto[]>> GetHistory(Guid id, CancellationToken ct) =>
        (await getHotstringHistory.ExecuteAsync(new GetHotstringHistoryQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Get one saved version of a hotstring, including its snapshot.</summary>
    [HttpGet("{id:guid}/history/{version:int}")]
    [ProducesResponseType(typeof(HotstringHistoryVersionDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HotstringHistoryVersionDto>> GetHistoryVersion(
        Guid id,
        int version,
        CancellationToken ct) =>
        (await getHotstringHistoryVersion.ExecuteAsync(
            new GetHotstringHistoryVersionQuery(id, version),
            ct)).ToProblemActionResult(this);

    /// <summary>Revert a hotstring to a saved version. Returns the updated representation.</summary>
    [HttpPost("{id:guid}/history/{version:int}/revert")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Revert(Guid id, int version, CancellationToken ct) =>
        (await revertHotstring.ExecuteAsync(new RevertHotstringCommand(id, version), ct)).ToProblemActionResult(this);

    /// <summary>List deleted hotstrings that can be restored from the Recycle Bin.</summary>
    [HttpGet("deleted")]
    [ProducesResponseType(typeof(DeletedHotstringDto[]), StatusCodes.Status200OK)]
    public async Task<ActionResult<DeletedHotstringDto[]>> ListDeleted(CancellationToken ct) =>
        (await listDeletedHotstrings.ExecuteAsync(new ListDeletedHotstringsQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Restore a deleted hotstring with its original id and links.</summary>
    [HttpPost("{id:guid}/restore")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Restore(Guid id, CancellationToken ct) =>
        (await restoreHotstring.ExecuteAsync(new RestoreHotstringCommand(id), ct)).ToProblemActionResult(this);

    /// <summary>Permanently remove a deleted hotstring's history.</summary>
    [HttpDelete("deleted/{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Purge(Guid id, CancellationToken ct)
    {
        Result result = await purgeDeletedHotstring.ExecuteAsync(new PurgeDeletedHotstringCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }

    /// <summary>Preview which hotstring lines a pasted/uploaded script would import.</summary>
    [HttpPost("import/preview")]
    [ProducesResponseType(typeof(HotstringImportPreviewDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<HotstringImportPreviewDto>> ImportPreview(
        [FromBody] PreviewHotstringImportRequestDto dto,
        CancellationToken ct) =>
        (await previewImport.ExecuteAsync(new PreviewHotstringImportCommand(dto.Script), ct))
            .ToProblemActionResult(this);

    /// <summary>Bulk-create the recognized hotstrings from a script into a profile target.</summary>
    [HttpPost("import")]
    [ProducesResponseType(typeof(HotstringImportResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<HotstringImportResultDto>> Import(
        [FromBody] ImportHotstringsRequestDto dto,
        CancellationToken ct) =>
        (await importHotstrings.ExecuteAsync(new ImportHotstringsCommand(dto), ct))
            .ToProblemActionResult(this);

    /// <summary>Preview the AutoHotkey snippet a hotstring definition would generate, without saving it.</summary>
    [HttpPost("preview")]
    [ProducesResponseType(typeof(HotstringPreviewDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<HotstringPreviewDto>> Preview(
        [FromBody] HotstringPreviewRequestDto dto,
        CancellationToken ct) =>
        (await previewHotstring.ExecuteAsync(new GetHotstringPreviewQuery(dto), ct)).ToProblemActionResult(this);
}
