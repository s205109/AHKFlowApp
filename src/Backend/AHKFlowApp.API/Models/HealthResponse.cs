namespace AHKFlowApp.API.Models;

public sealed record HealthResponse(
    string Status,
    string Version,
    string Environment,
    DateTimeOffset Timestamp,
    Dictionary<string, string> Checks,
    string? Tier = null);
