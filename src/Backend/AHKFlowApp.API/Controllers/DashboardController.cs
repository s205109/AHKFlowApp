using AHKFlowApp.API.Extensions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Queries.Dashboard;
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
public sealed class DashboardController(IMediator mediator) : ControllerBase
{
    /// <summary>Aggregated counts, weekly delta, 14-day buckets, and recent activity for the home dashboard.</summary>
    [HttpGet("stats")]
    [ProducesResponseType(typeof(DashboardStatsDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<DashboardStatsDto>> GetStats(CancellationToken ct) =>
        (await mediator.Send(new GetDashboardStatsQuery(), ct)).ToProblemActionResult(this);
}
