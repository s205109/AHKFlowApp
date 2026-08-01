using System.Xml.Linq;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class E2EPublishTargetTests
{
    [Fact]
    public void PublishBlazorForE2E_Target_AlwaysRunsAndCleansBeforePublish()
    {
        // Arrange
        var document = XDocument.Load(FindE2ETestProjectPath());

        // Act
        XElement target = FindElement(document, "Target", "Name", "PublishBlazorForE2E");
        List<XElement> tasks = [.. target.Elements()];
        XElement removeDir = target.Elements("RemoveDir").Single();
        XElement exec = target.Elements("Exec").Single();
        string command = exec.Attribute("Command")?.Value ?? string.Empty;

        // Assert
        target.Attribute("BeforeTargets")?.Value.Should().Be("VSTest");
        target.Attribute("Inputs").Should()
            .BeNull("an up-to-date check lets MSBuild skip the publish and serve a stale app");
        target.Attribute("Outputs").Should()
            .BeNull("an up-to-date check lets MSBuild skip the publish and serve a stale app");
        target.Elements("Touch").Should()
            .BeEmpty("the stamp and index.html proxy outputs no longer exist");

        removeDir.Attribute("Directories")?.Value.Should().Be("$(BlazorE2EPublishDir)");
        removeDir.Attribute("Condition")?.Value.Should().Be("'$(BlazorE2EPublishDir)' != ''");
        tasks.IndexOf(removeDir).Should().BeLessThan(
            tasks.IndexOf(exec),
            "cleaning after the publish would delete the app it just copied");

        command.Should().Contain("dotnet publish");
        command.Should().Contain("\"$(BlazorE2EProject)\"");
        command.Should().Contain("-c $(Configuration)");
        command.Should().NotContain(
            "--no-build",
            "--no-build reuses a stale trimmed assembly, so the published app can miss the latest source");
        command.Should().Contain("--no-restore");
        command.Should().Contain("-o \"$(BlazorE2EPublishDir)\"");
    }

    [Fact]
    public void PublishBlazorForE2E_ObsoleteIncrementalMachinery_IsAbsent()
    {
        // Arrange
        var document = XDocument.Load(FindE2ETestProjectPath());

        // Act
        List<string> itemNames =
        [
            .. document.Root!.Elements("ItemGroup").Elements().Select(element => element.Name.LocalName)
        ];
        List<string> propertyNames =
        [
            .. document.Root!.Elements("PropertyGroup").Elements().Select(element => element.Name.LocalName)
        ];

        // Assert
        itemNames.Should().NotContain("BlazorE2EPublishInput");
        propertyNames.Should().NotContain("BlazorE2EPublishStamp");
        propertyNames.Should().NotContain("BlazorE2EPublishIndex");
        propertyNames.Should().NotContain("BlazorE2EProjectDir");
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
