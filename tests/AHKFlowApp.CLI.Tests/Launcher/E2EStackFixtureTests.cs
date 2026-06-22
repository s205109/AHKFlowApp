using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class E2EStackFixtureTests
{
    [Fact]
    public void E2ETestCollection_SharesStackFixtureAcrossFlowClasses()
    {
        // Arrange
        string e2eDirectory = FindE2ETestProjectDirectory();
        string collectionSource = File.ReadAllText(Path.Combine(e2eDirectory, "E2ETestCollection.cs"));
        string[] flowTestFiles =
        [
            "HotstringsCrudFlowTests.cs",
            "HotstringsMobileFlowTests.cs",
            "HotkeysMobileFlowTests.cs",
        ];

        // Act
        string[] perClassFixtures = flowTestFiles
            .Where(file => File.ReadAllText(Path.Combine(e2eDirectory, file)).Contains("IClassFixture<StackFixture>", StringComparison.Ordinal))
            .ToArray();

        // Assert
        collectionSource.Should().Contain(": ICollectionFixture<StackFixture>");
        perClassFixtures.Should().BeEmpty("the browser/API/Spa stack must start once for the E2E collection, not once per flow class");
    }

    private static string FindE2ETestProjectDirectory()
    {
        string? directory = AppContext.BaseDirectory;

        while (!string.IsNullOrWhiteSpace(directory))
        {
            string candidate = Path.Combine(directory, "tests", "AHKFlowApp.E2E.Tests");
            if (Directory.Exists(candidate))
            {
                return candidate;
            }

            directory = Directory.GetParent(directory)?.FullName;
        }

        throw new InvalidOperationException("Could not locate tests/AHKFlowApp.E2E.Tests.");
    }
}
