using AHKFlowApp.API.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class HealthController(
    HealthCheckService healthCheckService,
    IHostEnvironment hostEnvironment) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<HealthResponse>> GetHealthAsync(CancellationToken cancellationToken)
    {
        HealthReport report = await healthCheckService.CheckHealthAsync(cancellationToken);

        var checks = report.Entries.ToDictionary(
            e => e.Key,
            e => e.Value.Status.ToString());

        var response = new HealthResponse(
            Status: report.Status.ToString(),
            Environment: hostEnvironment.EnvironmentName,
            Timestamp: DateTimeOffset.UtcNow,
            Checks: checks);

        return report.Status == HealthStatus.Unhealthy
            ? StatusCode(StatusCodes.Status503ServiceUnavailable, response)
            : Ok(response);
    }
}
