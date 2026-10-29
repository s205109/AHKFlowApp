using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

public sealed partial class PublishedConfigTests
{
    // Every other appsettings file is dev-only and stays out of the publish.
    private static readonly string[] RunTimeAppSettings =
    [
        "appsettings.json",
        "appsettings.Production.json",
        "appsettings.Test.json"
    ];

    [GeneratedRegex("\"url\"\\s*:\\s*\"(appsettings[^\"]*)\"")]
    private static partial Regex ManifestAppSettingsUrl();

    [Fact]
    public void PublishedWwwroot_AfterAnyE2ERun_HoldsOnlyRunTimeAppSettings()
    {
        // Arrange
        string wwwroot = StackFixture.ResolvePublishedWwwroot();

        // Act: top directory only, file names only
        string[] published = [.. Directory.EnumerateFiles(wwwroot, "appsettings*").Select(Path.GetFileName)!];

        // Assert
        published.Should().BeEquivalentTo(RunTimeAppSettings,
            "a dev-only appsettings file in the bundle advertises the test-auth switch; " +
            "add a new environment file to this list only if the published app needs it");
    }

    [Fact]
    public void ServiceWorkerManifest_AfterAnyE2ERun_ListsOnlyRunTimeAppSettings()
    {
        // Arrange
        string manifest = File.ReadAllText(Path.Combine(StackFixture.ResolvePublishedWwwroot(), "service-worker-assets.js"));

        // Act
        string[] listed = [.. ManifestAppSettingsUrl().Matches(manifest).Select(m => m.Groups[1].Value)];

        // Assert
        listed.Should().BeEquivalentTo(RunTimeAppSettings,
            "the service worker install requests every listed URL, so the manifest and the " +
            "publish folder must name the same appsettings files");
    }
}
