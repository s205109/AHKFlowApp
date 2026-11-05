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

    [GeneratedRegex(@"var bootFailureGraceMs = [^;]*window\.__ahkflowBootFailureGraceMs[^;]*:\s*10000;")]
    private static partial Regex GraceWithTenSecondFallback();

    [Fact]
    public void GraceFallback_IsTenSeconds()
    {
        string script = File.ReadAllText(GetBootScriptPath());

        GraceWithTenSecondFallback().IsMatch(script).Should().BeTrue(
            "bootBlazor.js must read window.__ahkflowBootFailureGraceMs and fall back to 10000 ms " +
            "when that value is not set. Production relies on the 10 s fallback.");
    }
}
