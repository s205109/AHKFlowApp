using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public static class ApiErrorMessageFactory
{
    public static string Build(ApiResultStatus status, ApiProblemDetails? problem) => status switch
    {
        // Each rule message names its own field by the label the owner sees, so the key, a
        // property name, would only repeat it. Each message ends in a period, so a single space
        // joins them.
        ApiResultStatus.Validation when problem?.Errors is { Count: > 0 } errors =>
            string.Join(" ", errors.SelectMany(kv => kv.Value)),
        ApiResultStatus.Validation => problem?.Detail ?? "The request was invalid.",
        // Entity-neutral fallbacks. Every page uses this helper, so naming one entity here put
        // "Hotstring not found." in front of someone deleting a known shortcut.
        ApiResultStatus.NotFound => problem?.Detail ?? "That item was not found.",
        ApiResultStatus.Conflict => problem?.Detail ?? "That item already exists.",
        ApiResultStatus.Unauthorized => "You are not signed in.",
        ApiResultStatus.Forbidden => "You do not have permission to perform this action.",
        ApiResultStatus.NetworkError => "Unable to reach the API. Check your connection and try again.",
        _ => problem?.Detail ?? "An unexpected error occurred.",
    };
}
