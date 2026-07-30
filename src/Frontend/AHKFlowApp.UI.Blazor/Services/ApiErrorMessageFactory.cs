using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

public static class ApiErrorMessageFactory
{
    public static string Build(ApiResultStatus status, ApiProblemDetails? problem) => status switch
    {
        ApiResultStatus.Validation when problem?.Errors is { Count: > 0 } errors =>
            string.Join("; ", errors.SelectMany(kv => kv.Value.Select(v => $"{FieldLabel(kv.Key)}: {v}"))),
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

    /// <summary>
    /// The part of a validation key a reader can use. FluentValidation names a nested property by
    /// its whole path, so a command wrapping a DTO produces "Input.Does" — the shape of the
    /// request object, which means nothing to the person reading the message. Only the last
    /// segment names the field they filled in.
    /// </summary>
    private static string FieldLabel(string key)
    {
        int lastDot = key.LastIndexOf('.');

        // A trailing dot leaves nothing to show, so keep the key as it came.
        return lastDot >= 0 && lastDot < key.Length - 1 ? key[(lastDot + 1)..] : key;
    }
}
