using System.Text.RegularExpressions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Constants;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Application.Tests.Constants;

/// <summary>
/// The catalog is shipped text that lands verbatim in a user's header, so these rules are
/// enforced here rather than by review. A preset that breaks one of them breaks the whole
/// generated script for whoever picked it.
/// </summary>
public sealed class HeaderPresetCatalogTests
{
    // The Blazor inserter owns the marker format. This literal only guards against a body
    // that would look like a marker to the picker's "already there" check.
    private const string OpenMarkerPrefix = "; --- AHKFlow preset:";

    private static readonly HeaderTokenRenderer.Context RenderContext = new(
        ProfileName: "Work",
        AppVersion: "1.2.3",
        HotstringCount: 4,
        HotkeyCount: 5,
        GeneratedAt: new DateTimeOffset(2026, 8, 4, 10, 0, 0, TimeSpan.Zero));

    public static TheoryData<string> PresetIds()
    {
        TheoryData<string> data = [];
        foreach (HeaderPreset preset in HeaderPresetCatalog.All)
            data.Add(preset.Id);
        return data;
    }

    private static HeaderPreset Preset(string id) =>
        HeaderPresetCatalog.All.Single(p => p.Id == id);

    [Fact]
    public void Catalog_IsNotEmpty()
    {
        HeaderPresetCatalog.All.Should().NotBeEmpty();
    }

    [Fact]
    public void Ids_AreUniqueAndKebabCase()
    {
        string[] ids = [.. HeaderPresetCatalog.All.Select(p => p.Id)];

        ids.Should().OnlyHaveUniqueItems();
        ids.Should().AllSatisfy(id =>
            Regex.IsMatch(id, "^[a-z0-9]+(-[a-z0-9]+)*$").Should().BeTrue($"'{id}' must be kebab-case"));
    }

    [Theory]
    [MemberData(nameof(PresetIds))]
    public void EveryField_IsFilledIn(string id)
    {
        HeaderPreset preset = Preset(id);

        preset.Name.Should().NotBeNullOrWhiteSpace();
        preset.Description.Should().NotBeNullOrWhiteSpace();
        preset.Tag.Should().NotBeNullOrWhiteSpace();
        preset.Body.Should().NotBeNullOrWhiteSpace();
    }

    [Theory]
    [MemberData(nameof(PresetIds))]
    public void Body_HasNoDoubledBraces(string id)
    {
        string body = Preset(id).Body;

        body.Should().NotContain("{{");
        body.Should().NotContain("}}");
    }

    [Theory]
    [MemberData(nameof(PresetIds))]
    public void Body_SurvivesHeaderRenderingUnchanged(string id)
    {
        string body = Preset(id).Body;

        new HeaderTokenRenderer().Render(body, RenderContext).Should().Be(body);
    }

    [Theory]
    [MemberData(nameof(PresetIds))]
    public void Body_RepeatsNoDirectiveFromTheDefaultHeader(string id)
    {
        HashSet<string> defaultDirectives = FirstWords(DefaultProfileTemplates.Header);

        FirstWords(Preset(id).Body).Should().NotIntersectWith(defaultDirectives);
    }

    [Theory]
    [MemberData(nameof(PresetIds))]
    public void Body_HasNoMarkerTextAndNoOuterBlankLines(string id)
    {
        string body = Preset(id).Body;

        body.Should().NotContain(OpenMarkerPrefix);
        body.Should().Be(body.Trim('\n', '\r', ' '));
    }

    // The first word of every line that is neither blank nor a comment: "#Requires",
    // "SendMode", and so on. Derived from the source, never hard-coded, so a change to the
    // default header cannot leave this test asserting yesterday's list.
    private static HashSet<string> FirstWords(string script) =>
    [
        .. script.Split('\n')
            .Select(line => line.Trim())
            .Where(line => line.Length > 0 && !line.StartsWith(';'))
            .Select(line => line.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries)[0])
    ];
}
