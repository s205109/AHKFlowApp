using System.Security.Claims;
using AHKFlowApp.Application.Abstractions;

namespace AHKFlowApp.API.Auth;

internal sealed class HttpContextCurrentUser(IHttpContextAccessor httpContextAccessor) : ICurrentUser
{
    private ClaimsPrincipal? User => httpContextAccessor.HttpContext?.User;

    public Guid? Oid
    {
        get
        {
            string? value = User?.FindFirstValue("http://schemas.microsoft.com/identity/claims/objectidentifier")
                     ?? User?.FindFirstValue("oid");
            return Guid.TryParse(value, out Guid guid) ? guid : null;
        }
    }

    public string? Email =>
        User?.FindFirstValue("preferred_username")
        ?? User?.FindFirstValue(ClaimTypes.Email);

    public string? Name =>
        User?.FindFirstValue(ClaimTypes.Name)
        ?? User?.FindFirstValue("name");

    public bool IsAuthenticated => User?.Identity?.IsAuthenticated ?? false;
}
