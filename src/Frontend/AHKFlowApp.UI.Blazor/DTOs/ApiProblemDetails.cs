namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record ApiProblemDetails(
    string? Type,
    string? Title,
    int? Status,
    string? Detail,
    string? Instance,
    IReadOnlyDictionary<string, string[]>? Errors);
