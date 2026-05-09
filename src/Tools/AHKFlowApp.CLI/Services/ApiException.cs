namespace AHKFlowApp.CLI.Services;

public sealed class ApiException(int statusCode, string? body)
    : Exception($"API returned {statusCode}.")
{
    public int StatusCode { get; } = statusCode;
    public string? Body { get; } = body;
}
