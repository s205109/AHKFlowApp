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
                    BrowserUrl: null),
                new ProjectLaunch(
                    "UI",
                    Path.Combine("src", "Frontend", "AHKFlowApp.UI.Blazor", "AHKFlowApp.UI.Blazor.csproj"),
                    "http",
                    "http://localhost:5601",
                    "http://localhost:5601")
            ]);
    }
}
