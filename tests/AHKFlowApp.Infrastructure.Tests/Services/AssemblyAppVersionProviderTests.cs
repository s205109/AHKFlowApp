using System.Reflection;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Infrastructure.Services;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.Infrastructure.Tests.Services;

public sealed class AssemblyAppVersionProviderTests
{
    [Fact]
    public void GetVersion_ReturnsNonEmptyString()
    {
        IAppVersionProvider sut = new AssemblyAppVersionProvider();

        string version = sut.GetVersion();

        version.Should().NotBeNullOrWhiteSpace();
    }

    [Fact]
    public void GetVersion_MatchesEntryAssemblyInformationalVersion()
    {
        string? expectedRaw = Assembly.GetEntryAssembly()?
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion;
        expectedRaw.Should().NotBeNullOrWhiteSpace(
            "test host should have an InformationalVersion attribute");

        int plus = expectedRaw!.IndexOf('+');
        string expected = plus >= 0 ? expectedRaw[..plus] : expectedRaw;

        new AssemblyAppVersionProvider().GetVersion().Should().Be(expected);
    }

    [Fact]
    public void ResolveVersion_ReturnsFallback_WhenAssemblyIsNull()
    {
        string result = AssemblyAppVersionProvider.ResolveVersion(null);

        result.Should().Be("0.0.0-dev");
    }

    [Fact]
    public void ResolveVersion_NeverContainsPlusSuffix()
    {
        string result = AssemblyAppVersionProvider.ResolveVersion(Assembly.GetEntryAssembly());

        result.Should().NotContain("+");
    }
}
