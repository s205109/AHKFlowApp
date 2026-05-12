using System.Net;
using Polly.Timeout;

namespace AHKFlowApp.CLI.Services;

internal static class CliApiFailureDetector
{
    private const string HtmlContentType = "text/html";

    public static bool ShouldRetry(Exception? exception, HttpResponseMessage? response) =>
        exception is HttpRequestException or TimeoutRejectedException
        || response?.StatusCode is HttpStatusCode.RequestTimeout
            or HttpStatusCode.TooManyRequests
            or HttpStatusCode.BadGateway
            or HttpStatusCode.ServiceUnavailable
            or HttpStatusCode.GatewayTimeout
        || IsStoppedWebAppResponse(response);

    public static bool IsStoppedWebAppResponse(ApiException exception) =>
        exception.StatusCode == (int)HttpStatusCode.Forbidden
        && IsHtmlContentType(exception.ContentType)
        && LooksLikeStoppedWebAppPage(exception.Body);

    private static bool IsStoppedWebAppResponse(HttpResponseMessage? response) =>
        response?.StatusCode == HttpStatusCode.Forbidden
        && IsHtmlContentType(response.Content.Headers.ContentType?.MediaType);

    private static bool IsHtmlContentType(string? contentType) =>
        contentType?.StartsWith(HtmlContentType, StringComparison.OrdinalIgnoreCase) == true;

    private static bool LooksLikeStoppedWebAppPage(string? body) =>
        !string.IsNullOrWhiteSpace(body)
        && (body.Contains("Web App - Unavailable", StringComparison.OrdinalIgnoreCase)
            || body.Contains("This web app is stopped.", StringComparison.OrdinalIgnoreCase));
}
