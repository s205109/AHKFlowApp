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
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken ct = default) =>
        (await mediator.Send(new ListHotstringsQuery(profileId, page, pageSize), ct)).ToProblemActionResult(this);

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
}
