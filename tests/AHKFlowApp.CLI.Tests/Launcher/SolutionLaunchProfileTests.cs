using System.Text.Json;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class SolutionLaunchProfileTests
{
    private const string ApiProjectPath = @"src\Backend\AHKFlowApp.API\AHKFlowApp.API.csproj";
    private const string UiProjectPath = @"src\Frontend\AHKFlowApp.UI.Blazor\AHKFlowApp.UI.Blazor.csproj";

    [Theory]
    [InlineData("Full Stack: Docker SQL (Recommended)", ApiProjectPath, "Docker SQL (Recommended)")]
    [InlineData("Full Stack: LocalDB SQL", ApiProjectPath, "LocalDB SQL")]
    public void FullStackApiProjects_PinDebugTargets(
        string solutionLaunchProfile,
        string projectPath,
        string expectedDebugTarget)
    {
        // Arrange
        using var document = JsonDocument.Parse(File.ReadAllText(FindSolutionLaunchPath()));

        // Act
        JsonElement project = FindProject(document, solutionLaunchProfile, projectPath);

        // Assert
        project.TryGetProperty("DebugTarget", out JsonElement debugTarget).Should().BeTrue();
        debugTarget.GetString().Should().Be(expectedDebugTarget);
        project.TryGetProperty("ProfileName", out _).Should().BeFalse();
    }

    [Theory]
    [InlineData("Full Stack: Docker SQL (Recommended)")]
    [InlineData("Full Stack: LocalDB SQL")]
    public void FullStackUiProjects_UseDefaultDebugTarget(string solutionLaunchProfile)
    {
        // Arrange
        using var document = JsonDocument.Parse(File.ReadAllText(FindSolutionLaunchPath()));

        // Act
        JsonElement project = FindProject(document, solutionLaunchProfile, UiProjectPath);

        // Assert
        project.TryGetProperty("DebugTarget", out _).Should().BeFalse();
        project.TryGetProperty("ProfileName", out _).Should().BeFalse();
    }

    private static string FindSolutionLaunchPath()
    {
        string? directory = AppContext.BaseDirectory;

        while (!string.IsNullOrWhiteSpace(directory))
        {
            string candidate = Path.Combine(directory, "AHKFlowApp.slnLaunch");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = Directory.GetParent(directory)?.FullName;
        }

        throw new InvalidOperationException("Could not locate AHKFlowApp.slnLaunch.");
    }

    private static JsonElement FindProject(
        JsonDocument document,
        string solutionLaunchProfile,
        string projectPath) =>
        document.RootElement
            .EnumerateArray()
            .Single(profile => profile.GetProperty("Name").GetString() == solutionLaunchProfile)
            .GetProperty("Projects")
            .EnumerateArray()
            .Single(project => project.GetProperty("Path").GetString() == projectPath);
}
