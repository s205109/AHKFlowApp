using AHKFlowApp.Launcher;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class LauncherPlanTests
{
    [Fact]
    public void Create_DefaultProfiles_ConfiguresApiAndFrontendLaunches()
    {
        IReadOnlyList<ProjectLaunch> launches = LauncherPlan.Create(
            apiProfile: "LocalDB SQL",
            uiProfile: "http");

        launches.Should().BeEquivalentTo(
            [
                new ProjectLaunch(
                    "API",
                    Path.Combine("src", "Backend", "AHKFlowApp.API", "AHKFlowApp.API.csproj"),
                    "LocalDB SQL",
                    "http://localhost:5600/swagger/index.html",
                    BrowserUrl: null,
                    UrlOverride: "http://localhost:5600"),
                new ProjectLaunch(
                    "UI",
                    Path.Combine("src", "Frontend", "AHKFlowApp.UI.Blazor", "AHKFlowApp.UI.Blazor.csproj"),
                    "http",
                    "http://localhost:5601",
                    "http://localhost:5601",
                    UrlOverride: "http://localhost:5601")
            ]);
    }

    [Fact]
    public void Create_WhenUrlsProvided_ConfiguresDynamicApiAndFrontendLaunches()
    {
        IReadOnlyList<ProjectLaunch> launches = LauncherPlan.Create(
            apiProfile: "LocalDB SQL",
            uiProfile: "http",
            apiUrl: "http://localhost:5604",
            frontendUrl: "http://localhost:5605");

        launches.Should().BeEquivalentTo(
            [
                new ProjectLaunch(
                    "API",
                    Path.Combine("src", "Backend", "AHKFlowApp.API", "AHKFlowApp.API.csproj"),
                    "LocalDB SQL",
                    "http://localhost:5604/swagger/index.html",
                    BrowserUrl: null,
                    UrlOverride: "http://localhost:5604"),
                new ProjectLaunch(
                    "UI",
                    Path.Combine("src", "Frontend", "AHKFlowApp.UI.Blazor", "AHKFlowApp.UI.Blazor.csproj"),
                    "http",
                    "http://localhost:5605",
                    "http://localhost:5605",
                    UrlOverride: "http://localhost:5605")
            ]);
    }

    [Fact]
    public void WorktreeLocalDevManifest_Parse_WhenValuesExist_ReturnsUrls()
    {
        const string text = """
            AHKFLOW_API_PORT=5604
            AHKFLOW_UI_PORT=5605
            AHKFLOW_API_URL=http://localhost:5604
            AHKFLOW_UI_URL=http://localhost:5605
            """;

        var manifest = WorktreeLocalDevManifest.Parse(text);

        manifest.ApiPort.Should().Be(5604);
        manifest.UiPort.Should().Be(5605);
        manifest.ApiUrl.Should().Be("http://localhost:5604");
        manifest.UiUrl.Should().Be("http://localhost:5605");
    }

    [Fact]
    public void WorktreeLocalDevManifest_Parse_WhenValuesAbsent_ReturnsDefaults()
    {
        var manifest = WorktreeLocalDevManifest.Parse("");

        manifest.ApiUrl.Should().Be("http://localhost:5600");
        manifest.UiUrl.Should().Be("http://localhost:5601");
    }

    [Fact]
    public void WorktreeLocalDevManifest_Parse_WhenOnlyPortsExist_ReturnsUrlsFromPorts()
    {
        const string text = """
            AHKFLOW_API_PORT=5608
            AHKFLOW_UI_PORT=5609
            """;

        var manifest = WorktreeLocalDevManifest.Parse(text);

        manifest.ApiPort.Should().Be(5608);
        manifest.UiPort.Should().Be(5609);
        manifest.ApiUrl.Should().Be("http://localhost:5608");
        manifest.UiUrl.Should().Be("http://localhost:5609");
    }

    [Fact]
    public void WorktreeLocalDevManifest_Parse_WhenInvalidPortsExist_IgnoresPorts()
    {
        const string text = """
            AHKFLOW_API_PORT=not-a-port
            AHKFLOW_UI_PORT=70000
            """;

        var manifest = WorktreeLocalDevManifest.Parse(text);

        manifest.ApiPort.Should().Be(5600);
        manifest.UiPort.Should().Be(5601);
        manifest.ApiUrl.Should().Be("http://localhost:5600");
        manifest.UiUrl.Should().Be("http://localhost:5601");
    }
}
