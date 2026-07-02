using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Commands.Hotstrings;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotstrings;
using Ardalis.Result;
using MediatR;
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
public sealed class HotstringsController(IMediator mediator) : ControllerBase
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
        CancellationToken ct = default) =>
        (await mediator.Send(new ListHotstringsQuery(
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
            categoryIds), ct)).ToProblemActionResult(this);

    /// <summary>Get a hotstring by id.</summary>
    [HttpGet("{id:guid}", Name = "GetHotstring")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HotstringDto>> Get(Guid id, CancellationToken ct) =>
        (await mediator.Send(new GetHotstringQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Create a new hotstring for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Create([FromBody] CreateHotstringDto dto, CancellationToken ct)
    {
        Result<HotstringDto> result = await mediator.Send(new CreateHotstringCommand(dto), ct);

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
        (await mediator.Send(new BulkDeleteHotstringsCommand(dto), ct)).ToProblemActionResult(this);

    /// <summary>Update an existing hotstring. Returns the updated representation.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Update(Guid id, [FromBody] UpdateHotstringDto dto, CancellationToken ct) =>
        (await mediator.Send(new UpdateHotstringCommand(id, dto), ct)).ToProblemActionResult(this);

    /// <summary>Delete a hotstring.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        Result result = await mediator.Send(new DeleteHotstringCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }

    /// <summary>List saved versions of a hotstring, newest first.</summary>
    [HttpGet("{id:guid}/history")]
    [ProducesResponseType(typeof(HistoryEntryDto[]), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HistoryEntryDto[]>> GetHistory(Guid id, CancellationToken ct) =>
        (await mediator.Send(new GetHotstringHistoryQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Get one saved version of a hotstring, including its snapshot.</summary>
    [HttpGet("{id:guid}/history/{version:int}")]
    [ProducesResponseType(typeof(HotstringHistoryVersionDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HotstringHistoryVersionDto>> GetHistoryVersion(
        Guid id,
        int version,
        CancellationToken ct) =>
        (await mediator.Send(new GetHotstringHistoryVersionQuery(id, version), ct)).ToProblemActionResult(this);

    /// <summary>Revert a hotstring to a saved version. Returns the updated representation.</summary>
    [HttpPost("{id:guid}/history/{version:int}/revert")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Revert(Guid id, int version, CancellationToken ct) =>
        (await mediator.Send(new RevertHotstringCommand(id, version), ct)).ToProblemActionResult(this);

    /// <summary>List deleted hotstrings that can be restored from the Recycle Bin.</summary>
    [HttpGet("deleted")]
    [ProducesResponseType(typeof(DeletedHotstringDto[]), StatusCodes.Status200OK)]
    public async Task<ActionResult<DeletedHotstringDto[]>> ListDeleted(CancellationToken ct) =>
        (await mediator.Send(new ListDeletedHotstringsQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Restore a deleted hotstring with its original id and links.</summary>
    [HttpPost("{id:guid}/restore")]
    [ProducesResponseType(typeof(HotstringDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotstringDto>> Restore(Guid id, CancellationToken ct) =>
        (await mediator.Send(new RestoreHotstringCommand(id), ct)).ToProblemActionResult(this);

    /// <summary>Permanently remove a deleted hotstring's history.</summary>
    [HttpDelete("deleted/{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Purge(Guid id, CancellationToken ct)
    {
        Result result = await mediator.Send(new PurgeDeletedHotstringCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
}
