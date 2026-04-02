namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HealthResponse
{
    public string Status { get; init; } = string.Empty;
    public string Environment { get; init; } = string.Empty;
    public DateTimeOffset Timestamp { get; init; }
    public Dictionary<string, string> Checks { get; init; } = [];
}
