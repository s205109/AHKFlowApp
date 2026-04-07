using AHKFlowApp.Infrastructure.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[AllowAnonymous]
public sealed class VersionController(IVersionService versionService) : ControllerBase
{
    [HttpGet]
    [ProducesResponseType(typeof(VersionResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<VersionResponse>> GetVersionAsync(CancellationToken cancellationToken)
    {
        string version = await versionService.GetVersionAsync(cancellationToken);
        return Ok(new VersionResponse(version));
    }

    public sealed record VersionResponse(string Version);
}
