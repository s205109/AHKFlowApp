using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Launcher;

public sealed class E2EStackFixtureTests
{
    /// <summary>
    /// The E2E stack starts once per collection, never once per flow class.
    /// </summary>
    /// <remarks>
    /// Backlog 132 split the suite into four collections, so there are now four stacks instead of
    /// one. The rule this test protects did not change: a stack is a collection's to own. A flow
    /// class that took an IClassFixture would start a browser, an API host and a SPA host of its
    /// own, and the run would pay for one stack per class.
    /// </remarks>
    [Fact]
    public void E2ECollections_ShareOneStackFixtureEach_AndNoFlowClassOwnsAStack()
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
            .Where(file => File.ReadAllText(Path.Combine(e2eDirectory, file)).Contains("IClassFixture<StackFixture", StringComparison.Ordinal))
            .ToArray();

        // Assert
        collectionSource.Should().Contain(": ICollectionFixture<StackFixture",
            "every E2E collection takes its stack as a collection fixture");
        perClassFixtures.Should().BeEmpty("the browser/API/Spa stack must start once per E2E collection, not once per flow class");
    }

    /// <summary>
    /// Each collection owns a distinct stack type, and each type names a distinct database.
    /// </summary>
    /// <remarks>
    /// xUnit builds one instance of a collection fixture per collection, so two collections naming
    /// the same fixture type still get an instance each. What they would share is the discriminator
    /// that type passes to StackFixture, and a discriminator names the database. Two collections
    /// running at the same time on one database would write over each other's rows.
    ///
    /// This is the cheap source-level guard, and it runs in Fast mode. The database names the four
    /// stacks really produce are checked in AHKFlowApp.E2E.Tests, in ApiFactoryTests.
    /// </remarks>
    [Fact]
    public void EveryE2ECollection_TakesItsOwnStackFixtureTypeAndDatabase()
    {
        // Arrange
        string e2eDirectory = FindE2ETestProjectDirectory();
        string collectionSource = File.ReadAllText(Path.Combine(e2eDirectory, "E2ETestCollection.cs"));

        // Act
        string[] fixtureTypes = ReadValues(collectionSource, ": ICollectionFixture<", '>');
        string[] discriminators = ReadValues(collectionSource, ": StackFixture(\"", '"');

        // Assert
        fixtureTypes.Should().NotBeEmpty();
        fixtureTypes.Should().OnlyHaveUniqueItems(
            "two collections sharing one fixture type would share one database while running together");

        discriminators.Should().HaveSameCount(fixtureTypes,
            "every stack fixture type passes StackFixture a discriminator of its own");
        discriminators.Should().OnlyHaveUniqueItems(
            "a discriminator names the database, so two stacks sharing one would share the rows");
    }

    private static string[] ReadValues(string source, string opening, char closing) =>
        source
            .Split(opening, StringSplitOptions.None)
            .Skip(1)
            .Select(part => part[..part.IndexOf(closing, StringComparison.Ordinal)])
            .ToArray();

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
