namespace AHKFlowApp.CLI.Services;

public sealed class ConsoleErrorHttpRetryStatusWriter(Func<TextWriter>? errorFactory = null)
    : IHttpRetryStatusWriter
{
    private readonly Func<TextWriter> _errorFactory = errorFactory ?? (() => Console.Error);

    public void WriteRetrying(string operationName, int retryAttempt, int maxRetryAttempts, TimeSpan delay)
    {
        TextWriter stderr = _errorFactory();
        stderr.WriteLine(HttpRetryStatusMessages.FormatRetrying(
            operationName,
            retryAttempt,
            maxRetryAttempts,
            delay));
    }
}
