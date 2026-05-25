namespace AHKFlowApp.Launcher;

internal sealed record ProjectLaunch(
    string Name,
    string ProjectPath,
    string LaunchProfile,
    string ReadyUrl,
    string? BrowserUrl);

internal static class LauncherPlan
{
    public const string ApiUrl = "http://localhost:5600";
    public const string FrontendUrl = "http://localhost:5601";

    public static IReadOnlyList<ProjectLaunch> Create(string apiProfile, string uiProfile) =>
        [
            new(
                "API",
                Path.Combine("src", "Backend", "AHKFlowApp.API", "AHKFlowApp.API.csproj"),
                apiProfile,
                $"{ApiUrl}/swagger/index.html",
                BrowserUrl: null),
            new(
                "UI",
                Path.Combine("src", "Frontend", "AHKFlowApp.UI.Blazor", "AHKFlowApp.UI.Blazor.csproj"),
                uiProfile,
                FrontendUrl,
                FrontendUrl)
        ];
}
