using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result.AspNetCore;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/dev")]
[Authorize]
[RequiredScope("access_as_user")]
public sealed class DevController(IMediator mediator) : ControllerBase
{
    /// <summary>Seeds a curated set of sample hotstrings for the authenticated user. Development only.</summary>
    [HttpPost("hotstrings/seed")]
    [ProducesResponseType(typeof(PagedList<HotstringDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PagedList<HotstringDto>>> SeedHotstrings(
        [FromQuery] bool reset = false,
        CancellationToken ct = default) =>
        (await mediator.Send(new SeedHotstringsCommand(reset), ct)).ToActionResult(this);
}
