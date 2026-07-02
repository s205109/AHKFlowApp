using System.Reflection;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Testing;

public sealed class IntegrationTraitGuardTests
{
    // Keep this v1 collection list in sync with docs/development/testing-workflow.md.
    private static readonly HashSet<string> IntegrationCollections =
    [
        "HotstringDb",
        "HotkeyDb",
        "ProfileDb",
        "CategoryDb",
        "DashboardDb",
        "DevDb",
        "PreferenceDb",
        "ScriptGeneratorDb",
        "HistoryDb",
    ];

    [Fact]
    public void DbCollectionTestClasses_HaveIntegrationCategoryTrait()
    {
        // Act
        string[] missingTraits = typeof(IntegrationTraitGuardTests).Assembly
            .GetTypes()
            .Where(IsConcreteTestClass)
            .Where(UsesIntegrationCollection)
            .Where(type => !HasIntegrationTrait(type))
            .Select(type => type.FullName ?? type.Name)
            .Order(StringComparer.Ordinal)
            .ToArray();

        // Assert
        missingTraits.Should().BeEmpty("DB-backed Application test classes must stay out of the fast local test slice");
    }

    private static bool IsConcreteTestClass(Type type) =>
        type.IsClass && !type.IsAbstract;

    private static bool UsesIntegrationCollection(Type type) =>
        type.GetCustomAttributesData()
            .Where(attribute => attribute.AttributeType == typeof(CollectionAttribute))
            .Any(attribute =>
                attribute.ConstructorArguments.Count == 1
                && attribute.ConstructorArguments[0].Value is string collectionName
                && IntegrationCollections.Contains(collectionName));

    private static bool HasIntegrationTrait(Type type) =>
        type.GetCustomAttributesData()
            .Where(attribute => attribute.AttributeType == typeof(TraitAttribute))
            .Any(attribute =>
                attribute.ConstructorArguments.Count == 2
                && string.Equals(attribute.ConstructorArguments[0].Value as string, "Category", StringComparison.Ordinal)
                && string.Equals(attribute.ConstructorArguments[1].Value as string, "Integration", StringComparison.Ordinal));
}
