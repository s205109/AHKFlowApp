using AHKFlowApp.API.Models;
using AHKFlowApp.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class HealthController(
    HealthCheckService healthCheckService,
    IHostEnvironment hostEnvironment,
    TimeProvider timeProvider,
    IVersionService versionService) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<HealthResponse>> GetHealthAsync(CancellationToken cancellationToken)
    {
        HealthReport report = await healthCheckService.CheckHealthAsync(cancellationToken);
        string version = await versionService.GetVersionAsync(cancellationToken);

        var checks = report.Entries.ToDictionary(
            e => e.Key,
            e => e.Value.Status == HealthStatus.Healthy
                ? e.Value.Status.ToString()
                : $"{e.Value.Status}: {e.Value.Description ?? e.Value.Exception?.Message ?? e.Value.Exception?.GetType().Name ?? "unknown error"}");

        var response = new HealthResponse(
            Status: report.Status.ToString(),
            Version: version,
            Environment: hostEnvironment.EnvironmentName,
            Timestamp: timeProvider.GetUtcNow(),
            Checks: checks);

        // Healthy and Degraded both return 200 — the API is functional in both cases.
        // Only Unhealthy (critical dependency down) returns 503.
        return report.Status == HealthStatus.Unhealthy
            ? StatusCode(StatusCodes.Status503ServiceUnavailable, response)
            : Ok(response);
    }
}
