using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.Commands.Preferences;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Preferences;
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
public sealed class PreferencesController(IMediator mediator) : ControllerBase
{
    /// <summary>Get preferences for the current user. Returns 404 if not yet configured — seed from local storage on first login.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(UserPreferenceDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<UserPreferenceDto>> Get(CancellationToken ct) =>
        (await mediator.Send(new GetUserPreferenceQuery(), ct)).ToProblemActionResult(this);

    /// <summary>Update preferences for the current user. Creates a record on first call.</summary>
    [HttpPut]
    [ProducesResponseType(typeof(UserPreferenceDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<UserPreferenceDto>> Update([FromBody] UpdateUserPreferenceDto dto, CancellationToken ct) =>
        (await mediator.Send(new UpdateUserPreferenceCommand(dto), ct)).ToProblemActionResult(this);
}
