using System.Xml.Linq;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class E2EPublishTargetTests
{
    [Fact]
    public void PublishBlazorForE2E_Target_IsIncrementalAndUsesBuiltFrontendOutput()
    {
        // Arrange
        var document = XDocument.Load(FindE2ETestProjectPath());

        // Act
        XElement target = FindElement(document, "Target", "Name", "PublishBlazorForE2E");
        XElement exec = target.Elements("Exec").Single();
        XElement touch = target.Elements("Touch").Single();
        string command = exec.Attribute("Command")?.Value ?? string.Empty;

        // Assert
        target.Attribute("BeforeTargets")?.Value.Should().Be("VSTest");
        target.Attribute("Inputs")?.Value.Should().Be("@(BlazorE2EPublishInput)");
        target.Attribute("Outputs")?.Value.Should().Be("$(BlazorE2EPublishStamp);$(BlazorE2EPublishIndex)");

        command.Should().Contain("dotnet publish");
        command.Should().Contain("\"$(BlazorE2EProject)\"");
        command.Should().Contain("-c $(Configuration)");
        command.Should().Contain("--no-build");
        command.Should().Contain("--no-restore");
        command.Should().Contain("-o \"$(BlazorE2EPublishDir)\"");

        touch.Attribute("Files")?.Value.Should().Be("$(BlazorE2EPublishStamp);$(BlazorE2EPublishIndex)");
        touch.Attribute("AlwaysCreate")?.Value.Should().Be("true");
    }

    [Fact]
    public void PublishBlazorForE2E_Inputs_TrackFrontendSourcesAndExcludeGeneratedOutput()
    {
        // Arrange
        var document = XDocument.Load(FindE2ETestProjectPath());

        // Act
        XElement item = document.Root!
            .Elements("ItemGroup")
            .Elements("BlazorE2EPublishInput")
            .Single();
        string exclude = item.Attribute("Exclude")?.Value ?? string.Empty;

        // Assert
        item.Attribute("Include")?.Value.Should().Be("$(BlazorE2EProjectDir)**/*");
        exclude.Should().Contain("$(BlazorE2EProjectDir)bin/**/*");
        exclude.Should().Contain("$(BlazorE2EProjectDir)obj/**/*");
    }

    private static XElement FindElement(
        XDocument document,
        string elementName,
        string attributeName,
        string attributeValue) =>
        document.Root!
            .Elements(elementName)
            .Single(element => element.Attribute(attributeName)?.Value == attributeValue);

    private static string FindE2ETestProjectPath()
    {
        string? directory = AppContext.BaseDirectory;

        while (!string.IsNullOrWhiteSpace(directory))
        {
            string candidate = Path.Combine(
                directory,
                "tests",
                "AHKFlowApp.E2E.Tests",
                "AHKFlowApp.E2E.Tests.csproj");
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = Directory.GetParent(directory)?.FullName;
        }

        throw new InvalidOperationException("Could not locate AHKFlowApp.E2E.Tests.csproj.");
    }
}
