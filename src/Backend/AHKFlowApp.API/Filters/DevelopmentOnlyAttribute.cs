using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace AHKFlowApp.API.Filters;

/// <summary>
/// Returns 404 for every action on the decorated controller outside the Development
/// environment, failing fast before the request reaches MediatR.
/// </summary>
public sealed class DevelopmentOnlyAttribute : ActionFilterAttribute
{
    public override void OnActionExecuting(ActionExecutingContext context)
    {
        IHostEnvironment env = context.HttpContext.RequestServices.GetRequiredService<IHostEnvironment>();
        if (!env.IsDevelopment())
            context.Result = new NotFoundResult();
    }
}
