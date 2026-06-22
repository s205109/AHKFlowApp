using System.Reflection;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.CLI.Tests.Testing;

public sealed class IntegrationTraitGuardTests
{
    [Fact]
    public void CliWebApiCollectionTestClasses_HaveIntegrationCategoryTrait()
    {
        // Act
        string[] missingTraits = typeof(IntegrationTraitGuardTests).Assembly
            .GetTypes()
            .Where(IsConcreteTestClass)
            .Where(UsesCliWebApiCollection)
            .Where(type => !HasIntegrationTrait(type))
            .Select(type => type.FullName ?? type.Name)
            .Order(StringComparer.Ordinal)
            .ToArray();

        // Assert
        missingTraits.Should().BeEmpty("CLI Web API integration tests must stay out of the fast local test slice");
    }

    private static bool IsConcreteTestClass(Type type) =>
        type.IsClass && !type.IsAbstract;

    private static bool UsesCliWebApiCollection(Type type) =>
        type.GetCustomAttributesData()
            .Where(attribute => attribute.AttributeType == typeof(CollectionAttribute))
            .Any(attribute =>
                attribute.ConstructorArguments.Count == 1
                && string.Equals(attribute.ConstructorArguments[0].Value as string, "CliWebApi", StringComparison.Ordinal));

    private static bool HasIntegrationTrait(Type type) =>
        type.GetCustomAttributesData()
            .Where(attribute => attribute.AttributeType == typeof(TraitAttribute))
            .Any(attribute =>
                attribute.ConstructorArguments.Count == 2
                && string.Equals(attribute.ConstructorArguments[0].Value as string, "Category", StringComparison.Ordinal)
                && string.Equals(attribute.ConstructorArguments[1].Value as string, "Integration", StringComparison.Ordinal));
}
