using System.Reflection;
using System.Xml.Linq;
using AHKFlowApp.Application.DTOs;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.API.Tests.OpenApi;

public sealed class ApplicationDtoXmlDocCoverageTests
{
    [Fact]
    public void PublicApplicationDtoTypesAndProperties_HaveXmlSummaries()
    {
        Assembly applicationAssembly = typeof(HotstringDto).Assembly;
        string xmlPath = Path.ChangeExtension(applicationAssembly.Location, ".xml");
        var xmlDocument = XDocument.Load(xmlPath);
        var documentedMembers = xmlDocument
            .Descendants("member")
            .Where(member => HasNonEmptySummary(member))
            .Select(member => member.Attribute("name")?.Value)
            .Where(name => name is not null)
            .ToHashSet();

        var missingDocs = applicationAssembly.GetTypes()
            .Where(type => type is { IsPublic: true, Namespace: "AHKFlowApp.Application.DTOs" })
            .SelectMany(type => RequiredMemberNames(type))
            .Where(memberName => !documentedMembers.Contains(memberName))
            .ToList();

        missingDocs.Should().BeEmpty(
            "public Application DTO contracts are exposed through OpenAPI schemas and must stay documented");
    }

    private static IEnumerable<string> RequiredMemberNames(Type type)
    {
        yield return $"T:{GetXmlTypeName(type)}";

        foreach (PropertyInfo property in type.GetProperties(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly))
        {
            if (property.GetIndexParameters().Length == 0)
                yield return $"P:{GetXmlTypeName(type)}.{property.Name}";
        }
    }

    private static string GetXmlTypeName(Type type)
    {
        string fullName = type.FullName ?? throw new InvalidOperationException($"Type {type} has no full name.");
        return fullName.Replace('+', '.');
    }

    private static bool HasNonEmptySummary(XElement member)
    {
        string? summary = member.Element("summary")?.Value;
        return !string.IsNullOrWhiteSpace(summary);
    }
}
