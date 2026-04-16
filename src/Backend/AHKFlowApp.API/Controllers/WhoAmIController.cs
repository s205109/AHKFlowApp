using AHKFlowApp.Application.Abstractions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Identity.Web.Resource;

namespace AHKFlowApp.API.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
[Authorize]
[RequiredScope("access_as_user")]
public sealed class WhoAmIController(ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public IActionResult Get() =>
        Ok(new WhoAmIResponse(currentUser.Oid, currentUser.Email, currentUser.Name, currentUser.IsAuthenticated));
}

public sealed record WhoAmIResponse(Guid? Oid, string? Email, string? Name, bool IsAuthenticated);
