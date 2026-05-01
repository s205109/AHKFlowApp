using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Commands.Profiles;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Profiles;
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
public sealed class ProfilesController(IMediator mediator) : ControllerBase
{
    /// <summary>List the current user's profiles. Lazily seeds a default profile on first call.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ProfileDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ProfileDto>>> List(CancellationToken ct) =>
        (await mediator.Send(new ListProfilesQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Get a profile by id.</summary>
    [HttpGet("{id:guid}", Name = "GetProfile")]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<ProfileDto>> Get(Guid id, CancellationToken ct) =>
        (await mediator.Send(new GetProfileQuery(id), ct)).ToProblemActionResult(this);

    /// <summary>Create a new profile for the current user.</summary>
    [HttpPost]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ProfileDto>> Create([FromBody] CreateProfileDto dto, CancellationToken ct)
    {
        Result<ProfileDto> result = await mediator.Send(new CreateProfileCommand(dto), ct);
        return result.IsSuccess
            ? CreatedAtRoute("GetProfile", new { id = result.Value.Id }, result.Value)
            : result.ToProblemActionResult(this);
    }

    /// <summary>Update a profile.</summary>
    [HttpPut("{id:guid}")]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ProfileDto>> Update(Guid id, [FromBody] UpdateProfileDto dto, CancellationToken ct) =>
        (await mediator.Send(new UpdateProfileCommand(id, dto), ct)).ToProblemActionResult(this);

    /// <summary>Delete a profile.</summary>
    [HttpDelete("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult> Delete(Guid id, CancellationToken ct)
    {
        Result result = await mediator.Send(new DeleteProfileCommand(id), ct);
        return result.IsSuccess ? NoContent() : result.ToProblemActionResult(this);
    }
}
