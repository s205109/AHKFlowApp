using System.Net;
using System.Net.Sockets;
using Polly.Timeout;

namespace AHKFlowApp.CLI.Services;

internal static class CliApiFailureDetector
{
    private const string HtmlContentType = "text/html";

    /// <summary>
    /// Decides whether a failed attempt may be retried. Retrying a non-idempotent request is only
    /// safe when the failure proves the API never received it — a gateway timeout or a dropped
    /// connection can both follow a write the origin already committed, so replaying them would
    /// create duplicates. Idempotent requests keep the broad retry set that wakes a cold API.
    /// </summary>
    public static bool ShouldRetry(
        Exception? exception,
        HttpResponseMessage? response,
        string? forbiddenBody,
        HttpMethod? requestMethod) =>
        IsIdempotent(requestMethod)
            ? IsTransientFailure(exception, response, forbiddenBody)
            : NeverReachedOrigin(exception, response, forbiddenBody);

    public static bool IsStoppedWebAppResponse(ApiException exception) =>
        exception.StatusCode == (int)HttpStatusCode.Forbidden
        && IsHtmlContentType(exception.ContentType)
        && LooksLikeStoppedWebAppPage(exception.Body);

    // Unknown method is treated as unsafe: better to fail a retryable read than to duplicate a write.
    private static bool IsIdempotent(HttpMethod? requestMethod) =>
        requestMethod is not null
        && (requestMethod == HttpMethod.Get
            || requestMethod == HttpMethod.Head
            || requestMethod == HttpMethod.Options
            || requestMethod == HttpMethod.Trace);

    private static bool IsTransientFailure(Exception? exception, HttpResponseMessage? response, string? forbiddenBody) =>
        exception is HttpRequestException or TimeoutRejectedException
        || response?.StatusCode is HttpStatusCode.RequestTimeout
            or HttpStatusCode.TooManyRequests
            or HttpStatusCode.BadGateway
            or HttpStatusCode.ServiceUnavailable
            or HttpStatusCode.GatewayTimeout
        || IsStoppedWebAppResponse(response, forbiddenBody);

    private static bool NeverReachedOrigin(Exception? exception, HttpResponseMessage? response, string? forbiddenBody) =>
        // The App Service front end serves the stopped-app page itself; the origin never ran.
        IsStoppedWebAppResponse(response, forbiddenBody)
        || (exception is HttpRequestException request && FailedBeforeSending(request));

    private static bool FailedBeforeSending(HttpRequestException exception) =>
        exception.HttpRequestError is HttpRequestError.NameResolutionError
            or HttpRequestError.SecureConnectionError
            or HttpRequestError.ProxyTunnelError
        // ConnectionError also covers mid-flight drops, so only a refused connect qualifies —
        // nothing was transmitted. A reset or abort may follow a fully sent request.
        || exception.InnerException is SocketException { SocketErrorCode: SocketError.ConnectionRefused };

    // Mirrors the ApiException overload: a bare 403 + text/html is not enough — the stopped-app
    // marker in the body must be present, or an unrelated HTML 403 (WAF, auth page) would be
    // mistaken for a cold App Service and retried.
    private static bool IsStoppedWebAppResponse(HttpResponseMessage? response, string? forbiddenBody) =>
        response?.StatusCode == HttpStatusCode.Forbidden
        && IsHtmlContentType(response.Content.Headers.ContentType?.MediaType)
        && LooksLikeStoppedWebAppPage(forbiddenBody);

    private static bool IsHtmlContentType(string? contentType) =>
        contentType?.StartsWith(HtmlContentType, StringComparison.OrdinalIgnoreCase) == true;

    private static bool LooksLikeStoppedWebAppPage(string? body) =>
        !string.IsNullOrWhiteSpace(body)
        && (body.Contains("Web App - Unavailable", StringComparison.OrdinalIgnoreCase)
            || body.Contains("This web app is stopped.", StringComparison.OrdinalIgnoreCase));
}
