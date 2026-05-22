using AHKFlowApp.Application.Abstractions;
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
public sealed class WhoAmIController(ICurrentUser currentUser) : ControllerBase
{
    /// <summary>Returns identity claims for the authenticated caller.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(WhoAmIResponse), StatusCodes.Status200OK)]
    public ActionResult<WhoAmIResponse> Get() =>
        Ok(new WhoAmIResponse(currentUser.Oid, currentUser.Email, currentUser.Name, currentUser.IsAuthenticated));
}

/// <summary>Identity details for the authenticated caller.</summary>
/// <param name="Oid">Entra object id (stable per-user GUID), or null when unauthenticated.</param>
/// <param name="Email">Caller email / preferred username, when present in the token.</param>
/// <param name="Name">Caller display name, when present in the token.</param>
/// <param name="IsAuthenticated">True when the request carried a valid token.</param>
public sealed record WhoAmIResponse(Guid? Oid, string? Email, string? Name, bool IsAuthenticated);
