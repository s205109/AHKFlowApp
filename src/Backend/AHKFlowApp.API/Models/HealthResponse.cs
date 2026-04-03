namespace AHKFlowApp.API.Models;

public sealed record HealthResponse(
    string Status,
    string Environment,
    DateTimeOffset Timestamp,
    Dictionary<string, string> Checks);
