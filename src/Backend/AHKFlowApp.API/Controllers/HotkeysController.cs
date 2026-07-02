using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Hotkeys;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Hotkeys;
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
public sealed class HotkeysController(
    IUseCase<ListHotkeysQuery, Result<PagedList<HotkeyDto>>> listHotkeys,
    IUseCase<GetHotkeyQuery, Result<HotkeyDto>> getHotkey,
    IUseCase<CreateHotkeyCommand, Result<HotkeyDto>> createHotkey,
    IUseCase<BulkDeleteHotkeysCommand, Result<BulkDeleteResultDto>> bulkDeleteHotkeys,
    IUseCase<UpdateHotkeyCommand, Result<HotkeyDto>> updateHotkey,
    IUseCase<DeleteHotkeyCommand, Result> deleteHotkey) : ControllerBase
{
    /// <summary>List hotkeys for the current user, optionally filtered by profile. Paginated.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(PagedList<HotkeyDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PagedList<HotkeyDto>>> List(
        [FromQuery] Guid? profileId,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string? sortField = null,
        [FromQuery] bool sortDescending = true,
        [FromQuery] string? descriptionFilter = null,
        [FromQuery] string? keyFilter = null,
        [FromQuery] string? parametersFilter = null,
        [FromQuery] HotkeyAction? action = null,
        [FromQuery] bool? appliesToAllProfiles = null,
        [FromQuery] bool? ctrl = null,
        [FromQuery] bool? alt = null,
        [FromQuery] bool? shift = null,
        [FromQuery] bool? win = null,
        [FromQuery] Guid[]? categoryIds = null,
        CancellationToken ct = default) =>
        (await listHotkeys.ExecuteAsync(new ListHotkeysQuery(
            profileId, search, page, pageSize,
            sortField, sortDescending,
            descriptionFilter, keyFilter, parametersFilter,
            action, appliesToAllProfiles,
            ctrl, alt, shift, win, categoryIds), ct)).ToProblemActionResult(this);

    /// <summary>Get a hotkey by id.</summary>
    [HttpGet("{id:guid}", Name = "GetHotkey")]
    [ProducesResponseType(typeof(HotkeyDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<HotkeyDto>> Get(Guid id, CancellationToken ct) =>
        (await getHotkey.ExecuteAsync(new GetHotkeyQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Create a new hotkey for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(HotkeyDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotkeyDto>> Create([FromBody] CreateHotkeyDto dto, CancellationToken ct)
    {
        Result<HotkeyDto> result = await createHotkey.ExecuteAsync(new CreateHotkeyCommand(dto), ct);

        return result.IsSuccess
            ? CreatedAtRoute("GetHotkey", new { id = result.Value.Id }, result.Value)
            : result.ToProblemActionResult(this);
    }

    /// <summary>Delete multiple hotkeys owned by the current user.</summary>
    [HttpPost("bulk-delete")]
    [ProducesResponseType(typeof(BulkDeleteResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<BulkDeleteResultDto>> BulkDelete(
        [FromBody] BulkDeleteRequestDto dto,
        CancellationToken ct) =>
        (await bulkDeleteHotkeys.ExecuteAsync(new BulkDeleteHotkeysCommand(dto), ct)).ToProblemActionResult(this);

    /// <summary>Update an existing hotkey. Returns the updated representation.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(HotkeyDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<HotkeyDto>> Update(Guid id, [FromBody] UpdateHotkeyDto dto, CancellationToken ct) =>
        (await updateHotkey.ExecuteAsync(new UpdateHotkeyCommand(id, dto), ct)).ToProblemActionResult(this);

    /// <summary>Delete a hotkey.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        Result result = await deleteHotkey.ExecuteAsync(new DeleteHotkeyCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
}
