using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public static class ApiErrorMessageFactory
{
    public static string Build(ApiResultStatus status, ApiProblemDetails? problem) => status switch
    {
        ApiResultStatus.Validation when problem?.Errors is { Count: > 0 } errors =>
            string.Join("; ", errors.SelectMany(kv => kv.Value.Select(v => $"{kv.Key}: {v}"))),
        ApiResultStatus.Validation => problem?.Detail ?? "The request was invalid.",
        ApiResultStatus.NotFound => problem?.Detail ?? "Hotstring not found.",
        ApiResultStatus.Conflict => problem?.Detail ?? "A hotstring with that trigger already exists.",
        ApiResultStatus.Unauthorized => "You are not signed in.",
        ApiResultStatus.Forbidden => "You do not have permission to perform this action.",
        ApiResultStatus.NetworkError => "Unable to reach the API. Check your connection and try again.",
        _ => problem?.Detail ?? "An unexpected error occurred.",
    };
}
