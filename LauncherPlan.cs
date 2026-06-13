namespace AHKFlowApp.Launcher;

internal sealed record ProjectLaunch(
    string Name,
    string ProjectPath,
    string LaunchProfile,
    string ReadyUrl,
    string? BrowserUrl,
    string UrlOverride);

internal static class LauncherPlan
{
    public const string ApiUrl = "http://localhost:5600";
    public const string FrontendUrl = "http://localhost:5601";

    public static IReadOnlyList<ProjectLaunch> Create(
        string apiProfile,
        string uiProfile,
        string apiUrl = ApiUrl,
        string frontendUrl = FrontendUrl) =>
        [
            new(
                "API",
                Path.Combine("src", "Backend", "AHKFlowApp.API", "AHKFlowApp.API.csproj"),
                apiProfile,
                $"{apiUrl}/swagger/index.html",
                BrowserUrl: null,
                UrlOverride: apiUrl),
            new(
                "UI",
                Path.Combine("src", "Frontend", "AHKFlowApp.UI.Blazor", "AHKFlowApp.UI.Blazor.csproj"),
                uiProfile,
                frontendUrl,
                frontendUrl,
                UrlOverride: frontendUrl)
        ];
}

internal sealed record WorktreeLocalDevManifest(int ApiPort, int UiPort, string ApiUrl, string UiUrl)
{
    private const string ApiPortKey = "AHKFLOW_API_PORT";
    private const string UiPortKey = "AHKFLOW_UI_PORT";
    private const string ApiUrlKey = "AHKFLOW_API_URL";
    private const string UiUrlKey = "AHKFLOW_UI_URL";

    public static WorktreeLocalDevManifest Parse(string text)
    {
        var values = text
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => parts[0].Trim(), parts => parts[1].Trim(), StringComparer.OrdinalIgnoreCase);

        int apiPort = TryGetPort(values, ApiPortKey) ?? GetPortFromUrl(LauncherPlan.ApiUrl);
        int uiPort = TryGetPort(values, UiPortKey) ?? GetPortFromUrl(LauncherPlan.FrontendUrl);
        string apiUrl = values.TryGetValue(ApiUrlKey, out string? configuredApiUrl)
            ? configuredApiUrl
            : $"http://localhost:{apiPort}";
        string uiUrl = values.TryGetValue(UiUrlKey, out string? configuredUiUrl)
            ? configuredUiUrl
            : $"http://localhost:{uiPort}";

        return new WorktreeLocalDevManifest(
            GetPortFromUrl(apiUrl, fallbackPort: apiPort),
            GetPortFromUrl(uiUrl, fallbackPort: uiPort),
            apiUrl,
            uiUrl);
    }

    private static int? TryGetPort(IReadOnlyDictionary<string, string> values, string key)
    {
        if (!values.TryGetValue(key, out string? value))
        {
            return null;
        }

        return int.TryParse(value, out int port) && port is > 0 and <= 65535
            ? port
            : null;
    }

    private static int GetPortFromUrl(string url, int? fallbackPort = null)
    {
        return Uri.TryCreate(url, UriKind.Absolute, out Uri? uri) && uri.Port > 0
            ? uri.Port
            : fallbackPort ?? 0;
    }
}
