namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HealthResponse(
    string Status,
    string Version,
    string Environment,
    DateTimeOffset Timestamp,
    Dictionary<string, string> Checks);
