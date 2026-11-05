using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests.Startup;

// The E2E Stack shortens the boot grace period through a window value, so its boot-failure tests
// do not wait 10 s. Production never sets that value. No E2E test can see the production value,
// because every E2E test that reaches the grace period sets the short one. This test reads the
// script itself, so it fails when the fallback changes or the override goes away.
public sealed partial class BootScriptGraceTests
{
    private static string GetBootScriptPath([CallerFilePath] string testFilePath = "")
    {
        string testDirectory = Path.GetDirectoryName(testFilePath)!;
        return Path.GetFullPath(Path.Combine(
            testDirectory, "..", "..", "..",
            "src", "Frontend", "AHKFlowApp.UI.Blazor", "wwwroot", "js", "bootBlazor.js"));
    }

    [GeneratedRegex(@"\bdefaultBootFailureGraceMs\s*=\s*(\d+)")]
    private static partial Regex DefaultGrace();

    [Fact]
    public void GraceFallback_IsTenSeconds()
    {
        string script = File.ReadAllText(GetBootScriptPath());

        Match fallback = DefaultGrace().Match(script);
        fallback.Success.Should().BeTrue("bootBlazor.js names its production wait defaultBootFailureGraceMs");
        fallback.Groups[1].Value.Should().Be("10000", "production waits 10 s after a failed download");
        script.Should().Contain("window.__ahkflowBootFailureGraceMs",
            "the E2E Stack shortens the wait through this value, and the fallback applies when it is not set");
    }
}
