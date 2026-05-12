namespace AHKFlowApp.CLI.Services;

public static class HttpRetryStatusMessages
{
    public static string FormatRetrying(
        string operationName,
        int retryAttempt,
        int maxRetryAttempts,
        TimeSpan delay)
    {
        int roundedSeconds = Math.Max(1, (int)Math.Ceiling(delay.TotalSeconds));
        return $"The API may be cold-starting. Retrying {operationName} request ({retryAttempt}/{maxRetryAttempts}) in {roundedSeconds}s...";
    }
}
