using System.Text.RegularExpressions;
using AHKFlowApp.E2E.Tests.Fixtures;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.E2E.Tests;

/// <summary>
/// Keeps the rule from ADR 0017: an E2E page is opened only through the diagnosed helper.
///
/// This reads source as text to find the banned call, and it is the only test in this repository
/// that does. The exemption is read from the compiled class instead. A Pester suite
/// would have been the usual home for a rule about how the repository is written, but
/// .githooks/pre-push.ps1 runs the Fast slice and not the PowerShell suites, so a suite would stay
/// silent until CI. The person who breaks this rule is writing an E2E test and running the E2E
/// slice, and that is the moment to tell them.
/// </summary>
public sealed class FirstPageLoadAdoptionTests
{
    private const string BannedCall = "NewPageAsync";

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

    /// <summary>
    /// The scanner itself. NoTestOpensAPageItself runs it over the real project, and
    /// TheCheck_FailsAFileThatOpensAPageItself runs it over fixtures, so both exercise one code path.
    /// </summary>
    /// <param name="files">Each file's name without extension, and its source text.</param>
    /// <param name="resolveType">Finds the class a file declares, by the file's name.</param>
    private static List<string> FindOffenders(
        IEnumerable<(string Name, string Source)> files,
        Func<string, Type?> resolveType)
    {
        List<string> offenders = [];

        foreach ((string name, string source) in files)
        {
            if (!source.Contains(BannedCall, StringComparison.Ordinal))
            {
                continue;
            }

            // Reflection, not text. A comment or a string can spell the attribute's name, but only a
            // real attribute on the compiled class can be read back here. A file whose class cannot
            // be found fails closed, because nothing proves it is exempt.
            if (resolveType(name)?.IsDefined(typeof(OpensPagesWithoutDiagnosisAttribute), inherit: false) == true)
            {
                continue;
            }

            offenders.Add(name);
        }

        return offenders;
    }

    [Fact]
    public void NoTestOpensAPageItself()
    {
        List<string> offenders = FindOffenders(
            TestFiles().Select(file => (Path.GetFileNameWithoutExtension(file), File.ReadAllText(file))),
            name => typeof(FirstPageLoadAdoptionTests).Assembly.GetType($"AHKFlowApp.E2E.Tests.{name}"));

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

    // The fixture classes the scanner resolves to. Only the real attribute on a real class may
    // exempt a file, so these carry the attribute, or do not, exactly as their names say.
    [OpensPagesWithoutDiagnosis("A fixture for TheCheck_FailsAFileThatOpensAPageItself.")]
    private sealed class AnnotatedFixture;

    private sealed class UnannotatedFixture;

    // Without this, the check could quietly stop checking and every run would stay green. It calls
    // FindOffenders itself, not a copy of its rule, so a change to the scanner is a change here.
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

        // The review finding. The attribute's name appears only in a comment and in a string, and
        // the class itself carries nothing. A text match exempted this file.
        string mentionsTheAttributeOnly = """
            // TODO: decide whether this needs OpensPagesWithoutDiagnosis.
            public sealed class PretendMentionTests
            {
                private const string Note = "[OpensPagesWithoutDiagnosis(\"not really\")]";
                public async Task Open() { IPage page = await ctx.NewPageAsync(); }
            }
            """;

        Dictionary<string, Type> declared = new()
        {
            ["Offender"] = typeof(UnannotatedFixture),
            ["Exempt"] = typeof(AnnotatedFixture),
            ["Compliant"] = typeof(UnannotatedFixture),
            ["MentionsTheAttributeOnly"] = typeof(UnannotatedFixture),
        };

        List<string> offenders = FindOffenders(
            [
                ("Offender", offender),
                ("Exempt", exempt),
                ("Compliant", compliant),
                ("MentionsTheAttributeOnly", mentionsTheAttributeOnly),
                ("DeclaresNoMatchingClass", offender),
            ],
            name => declared.GetValueOrDefault(name));

        // A file whose class cannot be found fails closed. Nothing proves it is exempt.
        offenders.Should().BeEquivalentTo(
            ["Offender", "MentionsTheAttributeOnly", "DeclaresNoMatchingClass"],
            "a bare NewPageAsync is caught, a comment or string naming the attribute is not an "
            + "exemption, the real attribute is, and the helper is the sanctioned route");

        TestClassDeclaration.Matches(offender + exempt).Count.Should().Be(2,
            "the one-class-per-file check must see two classes when there are two");
    }
}
