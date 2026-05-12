namespace AHKFlowApp.CLI.Services;

public static class ApiMessages
{
    public const string RequestTimedOut =
        "The API did not respond after multiple retries and may still be cold-starting. Wait a moment and try again.";

    public const string WebAppUnavailable =
        "The API is still unavailable after multiple retries. The Azure Web App may be stopped or still starting. Wait a moment and try again.";
}
