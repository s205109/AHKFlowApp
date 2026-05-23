using AHKFlowApp.API.Extensions;
using AHKFlowApp.API.Filters;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.DTOs;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/dev")]
[DevelopmentOnly]
[Authorize]
[RequiredScope("access_as_user")]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
[ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status403Forbidden)]
public sealed class DevController(IMediator mediator) : ControllerBase
{
    /// <summary>Seeds a curated set of sample hotstrings for the authenticated user. Development only.</summary>
    [HttpPost("hotstrings/seed")]
    [ProducesResponseType(typeof(PagedList<HotstringDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PagedList<HotstringDto>>> SeedHotstrings(
        [FromQuery] bool reset = false,
        CancellationToken ct = default) =>
        (await mediator.Send(new SeedHotstringsCommand(reset), ct)).ToProblemActionResult(this);

    /// <summary>Seeds the eight default categories for the authenticated user. Development only.</summary>
    [HttpPost("categories/seed")]
    [ProducesResponseType(typeof(IReadOnlyList<CategoryDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<IReadOnlyList<CategoryDto>>> SeedCategories(
        [FromQuery] bool reset = false,
        CancellationToken ct = default) =>
        (await mediator.Send(new SeedCategoriesCommand(reset), ct)).ToProblemActionResult(this);

    /// <summary>Seeds 12 sample hotkeys for the authenticated user. Development only.</summary>
    [HttpPost("hotkeys/seed")]
    [ProducesResponseType(typeof(PagedList<HotkeyDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PagedList<HotkeyDto>>> SeedHotkeys(
        [FromQuery] bool reset = false,
        CancellationToken ct = default) =>
        (await mediator.Send(new SeedHotkeysCommand(reset), ct)).ToProblemActionResult(this);

    /// <summary>Runs the full seed pipeline (categories + hotstrings + hotkeys) in a single transaction. Development only.</summary>
    [HttpPost("seed-all")]
    [ProducesResponseType(typeof(SeedAllResultDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<SeedAllResultDto>> SeedAll(
        [FromQuery] bool reset = false,
        CancellationToken ct = default) =>
        (await mediator.Send(new SeedAllCommand(reset), ct)).ToProblemActionResult(this);
}
