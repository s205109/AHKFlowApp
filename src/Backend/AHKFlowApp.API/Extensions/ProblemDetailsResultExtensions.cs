using Ardalis.Result;
using Microsoft.AspNetCore.Mvc;

namespace AHKFlowApp.API.Extensions;

/// <summary>
/// Maps Ardalis.Result outcomes to IActionResult values carrying RFC 9457 Problem Details
/// for all non-success statuses. Controllers use this instead of the default
/// <c>Ardalis.Result.AspNetCore.ToActionResult</c> so every error response shares the
/// same shape as <c>GlobalExceptionMiddleware</c>: type, title, status, detail, instance, traceId.
/// </summary>
internal static class ProblemDetailsResultExtensions
{
    // RFC 9110 section URIs — same pattern the exception middleware uses.
    internal const string TypeBadRequest = "https://tools.ietf.org/html/rfc9110#section-15.5.1";
    internal const string TypeUnauthorized = "https://tools.ietf.org/html/rfc9110#section-15.5.2";
    internal const string TypeForbidden = "https://tools.ietf.org/html/rfc9110#section-15.5.4";
    internal const string TypeNotFound = "https://tools.ietf.org/html/rfc9110#section-15.5.5";
    internal const string TypeConflict = "https://tools.ietf.org/html/rfc9110#section-15.5.10";
    internal const string TypeServerError = "https://tools.ietf.org/html/rfc9110#section-15.6.1";

    public static ActionResult<T> ToProblemActionResult<T>(this Result<T> result, ControllerBase controller) =>
        result.IsSuccess
            ? new OkObjectResult(result.Value)
            : BuildProblem(result.Status, result.Errors, result.ValidationErrors, controller.HttpContext);

    public static ActionResult ToProblemActionResult(this Result result, ControllerBase controller) =>
        result.IsSuccess
            ? new OkResult()
            : BuildProblem(result.Status, result.Errors, result.ValidationErrors, controller.HttpContext);

    private static ObjectResult BuildProblem(
        ResultStatus status,
        IEnumerable<string> errors,
        IEnumerable<ValidationError> validationErrors,
        HttpContext http)
    {
        ProblemDetails pd = status switch
        {
            ResultStatus.NotFound => Build(StatusCodes.Status404NotFound, TypeNotFound, "Resource not found", errors.FirstOrDefault()),
            ResultStatus.Conflict => Build(StatusCodes.Status409Conflict, TypeConflict, "Conflict", errors.FirstOrDefault()),
            ResultStatus.Unauthorized => Build(StatusCodes.Status401Unauthorized, TypeUnauthorized, "Unauthorized", null),
            ResultStatus.Forbidden => Build(StatusCodes.Status403Forbidden, TypeForbidden, "Forbidden", null),
            ResultStatus.Invalid => BuildValidation(validationErrors),
            _ => Build(StatusCodes.Status500InternalServerError, TypeServerError, "An unexpected error occurred", errors.FirstOrDefault())
        };

        pd.Instance = http.Request.Path;
        pd.Extensions["traceId"] = http.TraceIdentifier;

        return new ObjectResult(pd)
        {
            StatusCode = pd.Status,
            ContentTypes = { "application/problem+json" }
        };
    }

    private static ProblemDetails Build(int status, string type, string title, string? detail) =>
        new()
        {
            Status = status,
            Type = type,
            Title = title,
            Detail = detail
        };

    private static ValidationProblemDetails BuildValidation(IEnumerable<ValidationError> errors)
    {
        var pd = new ValidationProblemDetails
        {
            Status = StatusCodes.Status400BadRequest,
            Type = TypeBadRequest,
            Title = "Validation failed",
            Detail = "See the errors field for details."
        };

        foreach (IGrouping<string, ValidationError> g in errors.GroupBy(e => e.Identifier ?? string.Empty))
        {
            pd.Errors[g.Key] = g.Select(e => e.ErrorMessage).ToArray();
        }

        return pd;
    }
}
