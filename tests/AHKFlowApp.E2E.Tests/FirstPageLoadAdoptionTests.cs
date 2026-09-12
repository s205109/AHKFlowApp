using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

/// <summary>
/// Keeps the rule from ADR 0017: an E2E page is opened only through the diagnosed helper.
///
/// This reads source as text, and it is the only test in this repository that does. A Pester suite
/// would have been the usual home for a rule about how the repository is written, but
/// .githooks/pre-push.ps1 runs the Fast slice and not the PowerShell suites, so a suite would stay
/// silent until CI. The person who breaks this rule is writing an E2E test and running the E2E
/// slice, and that is the moment to tell them.
/// </summary>
public sealed class FirstPageLoadAdoptionTests
{
    private const string BannedCall = "NewPageAsync";
    private const string ExemptionAttribute = "OpensPagesWithoutDiagnosis";

    // Matches a top-level class declaration, which is how the per-file exemption stays safe. See
    // EveryTestFile_HoldsExactlyOneTestClass.
    private static readonly Regex TestClassDeclaration =
        new(@"^\s*(public|internal)\s+(sealed\s+)?class\s+\w*Tests\b", RegexOptions.Multiline, TimeSpan.FromSeconds(5));

    /// <summary>
    /// The project's own source folder. AppContext.BaseDirectory is bin/{Configuration}/net10.0,
    /// so the project root is three levels up. Resolved rather than assumed, so a retarget moves
    /// this once and loudly.
    /// </summary>
    private static string ProjectRoot() => Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", ".."));

    /// <summary>
    /// The test classes, and only those.
    /// </summary>
    /// <remarks>
    /// TopDirectoryOnly is doing real work, not saving time: it is what keeps Fixtures/ out of the
    /// scan. FirstPageLoad.cs lives there and calls NewPageAsync, because it is the one place that
    /// may. Changing this to AllDirectories makes the helper itself an offender.
    ///
    /// This file is left out too, and for the same kind of reason. It holds the banned call and
    /// three class declarations inside string literals, because TheCheck_FailsAFileThatOpensAPageItself
    /// runs the rule against text it controls. Those literals are data, not code, and scanning them
    /// would make this file fail both checks while breaking nothing. This file is not a flow test
    /// and opens no page, so nothing is lost by skipping it.
    /// </remarks>
    private static IEnumerable<string> TestFiles() =>
        Directory.EnumerateFiles(ProjectRoot(), "*.cs", SearchOption.TopDirectoryOnly)
            .Where(file => Path.GetFileName(file) != "FirstPageLoadAdoptionTests.cs");

    [Fact]
    public void NoTestOpensAPageItself()
    {
        List<string> offenders = [];

        foreach (string file in TestFiles())
        {
            string source = File.ReadAllText(file);

            if (!source.Contains(BannedCall, StringComparison.Ordinal))
            {
                continue;
            }

            if (source.Contains(ExemptionAttribute, StringComparison.Ordinal))
            {
                continue;
            }

            offenders.Add(Path.GetFileName(file));
        }

        offenders.Should().BeEmpty(
            "every first page load goes through FirstPageLoad.OpenAsync, so the failure says why the "
            + "app did not start. A class that must open a page itself carries "
            + "[OpensPagesWithoutDiagnosis(\"...\")]. See docs/adr/0017-an-e2e-page-is-opened-only-through-the-diagnosed-helper.md");
    }

    // The exemption is read per file, which is only safe while a file holds one test class. This
    // asserts the fact instead of assuming it: a file that grows a second class fails here rather
    // than being exempted in silence.
    [Fact]
    public void EveryTestFile_HoldsExactlyOneTestClass()
    {
        Dictionary<string, int> counts = [];

        foreach (string file in TestFiles())
        {
            int found = TestClassDeclaration.Matches(File.ReadAllText(file)).Count;
            if (found > 1)
            {
                counts[Path.GetFileName(file)] = found;
            }
        }

        counts.Should().BeEmpty("FirstPageLoadAdoptionTests reads the exemption attribute per file");
    }

    // Without this, the check could quietly stop checking and every run would stay green.
    [Fact]
    public void TheCheck_FailsAFileThatOpensAPageItself()
    {
        string offender = """
            public sealed class PretendFlowTests
            {
                public async Task Open() { IPage page = await ctx.NewPageAsync(); }
            }
            """;

        string exempt = """
            [OpensPagesWithoutDiagnosis("It breaks the boot on purpose.")]
            public sealed class PretendExemptTests
            {
                public async Task Open() { IPage page = await ctx.NewPageAsync(); }
            }
            """;

        string compliant = """
            public sealed class PretendGoodTests
            {
                public async Task Open() { IPage page = await FirstPageLoad.OpenAsync(ctx, url); }
            }
            """;

        // Same three decisions the [Fact] above makes, run against text this test controls.
        static bool IsOffender(string source) =>
            source.Contains(BannedCall, StringComparison.Ordinal)
            && !source.Contains(ExemptionAttribute, StringComparison.Ordinal);

        IsOffender(offender).Should().BeTrue("a bare NewPageAsync with no attribute is the thing this catches");
        IsOffender(exempt).Should().BeFalse("the attribute is the opt-out");
        IsOffender(compliant).Should().BeFalse("the helper is the sanctioned route");

        TestClassDeclaration.Matches(offender + exempt).Count.Should().Be(2,
            "the one-class-per-file check must see two classes when there are two");
    }
}
