namespace AHKFlowApp.UI.Blazor.Startup;

/// <summary>
/// Why the app cannot start normally — drives the message shown by <see cref="StartupError"/>.
/// </summary>
public enum StartupErrorReason
{
    /// <summary>Frontend Azure AD configuration is absent/empty (no appsettings.Development.json).</summary>
    MissingFrontendConfig,

    /// <summary>Frontend Azure AD configuration still contains <c>&lt;placeholder&gt;</c> values.</summary>
    PlaceholderConfig,

    /// <summary>The API could not be reached (down, or CORS not configured on the backend).</summary>
    BackendUnreachable,

    /// <summary>An unexpected error was caught by the global error boundary.</summary>
    Unexpected
}
