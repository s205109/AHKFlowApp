namespace AHKFlowApp.CLI.Services;

public interface IHttpRetryStatusWriter
{
    void WriteRetrying(string operationName, int retryAttempt, int maxRetryAttempts, TimeSpan delay);
}
