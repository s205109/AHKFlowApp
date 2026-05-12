namespace AHKFlowApp.CLI.Services;

public sealed class ApiException(int statusCode, string? body, string? contentType = null)
    : Exception($"API returned {statusCode}.")
{
    public int StatusCode { get; } = statusCode;
    public string? Body { get; } = body;
    public string? ContentType { get; } = contentType;
}
