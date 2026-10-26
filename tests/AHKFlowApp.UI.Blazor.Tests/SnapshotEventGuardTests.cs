using System.Reflection;
using System.Text.RegularExpressions;
using AngleSharp.Dom;
using Bunit;
using FluentAssertions;
using Xunit;

namespace AHKFlowApp.UI.Blazor.Tests;

/// <summary>
/// Keeps the bUnit rule from backlog item 187: an event on a snapshot element runs inside
/// InvokeAsync, together with the lookup that found it.
///
/// A snapshot element comes from FindAll, or from a child lookup such as QuerySelector or
/// Children. bUnit never refreshes it, so after a render it can hold a handler ID the renderer
/// has removed. This reads the test sources as text to find such an event. The event method names
/// are read from the compiled bUnit assembly, so a bUnit upgrade cannot leave an old list behind.
///
/// This file is left out of the scan. Its fixtures are string literals that hold the very calls
/// the rule bans, and they are data, not code.
/// </summary>
public sealed class SnapshotEventGuardTests
{
    private static readonly TimeSpan MatchTimeout = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Every bUnit event method that takes an element. bUnit generates them at compile time, so its
    /// source holds no list, and the built assembly is the only complete one. No name is removed.
    /// A name that is also some other method is a question for a person, not a silent filter.
    /// </summary>
    private static readonly IReadOnlySet<string> EventMethodNames =
        new[] { typeof(EventHandlerDispatchExtensions), typeof(TriggerEventDispatchExtensions) }
            .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.Static))
            .Where(method => method.GetParameters() is [{ } first, ..] && first.ParameterType == typeof(IElement))
            .Select(method => method.Name)
            .ToHashSet(StringComparer.Ordinal);

    // A lookup that returns a snapshot: FindAll, or a child lookup on any element.
    private static readonly Regex Lookup = new(
        @"\bFindAll\s*(?:<[^<>()]*>)?\s*\(|\.(?:QuerySelectorAll|QuerySelector|Closest)\s*(?:<[^<>()]*>)?\s*\(|\.(?:Children|ParentElement|NextElementSibling|PreviousElementSibling)\b",
        RegexOptions.None, MatchTimeout);

    // Declared after EventMethodNames on purpose. Static fields start in the order they are written.
    private static readonly Regex EventCall = new(
        $@"\.(?<name>{string.Join('|', EventMethodNames.Select(Regex.Escape))})\s*\(",
        RegexOptions.None, MatchTimeout);

    private static readonly Regex InvokeCall = new(@"\bInvokeAsync\s*\(", RegexOptions.None, MatchTimeout);

    /// <summary>
    /// The project's own source folder. AppContext.BaseDirectory is bin/{Configuration}/net10.0,
    /// so the project root is three levels up, as in FirstPageLoadAdoptionTests.
    /// </summary>
    private static string ProjectRoot() => Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", ".."));

    /// <summary>
    /// Blanks every character inside a comment, a string literal or a char literal, so a paren or a
    /// semicolon there cannot move a boundary. Newlines and delimiters stay, so every offset and
    /// every line number is the same as in the source. An interpolated string's holes are blanked
    /// with the rest of the string.
    /// </summary>
    private static string Mask(string source)
    {
        char[] masked = source.ToCharArray();
        int i = 0;

        while (i < source.Length)
        {
            if (source.AsSpan(i).StartsWith("//"))
            {
                int end = source.IndexOf('\n', i);
                i = Blank(masked, i + 2, end < 0 ? source.Length : end);
            }
            else if (source.AsSpan(i).StartsWith("/*"))
            {
                int end = source.IndexOf("*/", i + 2, StringComparison.Ordinal);
                i = end < 0 ? Blank(masked, i + 2, source.Length) : Blank(masked, i + 2, end) + 2;
            }
            else if (source[i] == '\'')
            {
                i = Blank(masked, i + 1, EscapedLiteralEnd(source, i + 1, '\'')) + 1;
            }
            else if (source[i] is '"' or '$' or '@')
            {
                i = MaskString(source, masked, i);
            }
            else
            {
                i++;
            }
        }

        return new string(masked);
    }

    // Masks the string literal that starts at i, after any $ and @ prefix, and returns the offset
    // just past it. Returns i + 1 when no string starts at i.
    private static int MaskString(string source, char[] masked, int i)
    {
        int quote = i;
        while (quote < source.Length && source[quote] is '$' or '@')
        {
            quote++;
        }

        if (quote >= source.Length || source[quote] != '"')
        {
            return i + 1;
        }

        bool verbatim = source.AsSpan(i, quote - i).Contains('@');
        int quotes = 0;
        while (quote + quotes < source.Length && source[quote + quotes] == '"')
        {
            quotes++;
        }

        if (!verbatim && quotes >= 3)
        {
            string delimiter = new('"', quotes);
            int close = source.IndexOf(delimiter, quote + quotes, StringComparison.Ordinal);
            return close < 0
                ? Blank(masked, quote + quotes, source.Length)
                : Blank(masked, quote + quotes, close) + quotes;
        }

        if (verbatim)
        {
            // A doubled quote is an escaped quote. A backslash is a plain character.
            int k = quote + 1;
            while (k < source.Length && !(source[k] == '"' && (k + 1 >= source.Length || source[k + 1] != '"')))
            {
                k += source[k] == '"' ? 2 : 1;
            }

            return Blank(masked, quote + 1, k) + 1;
        }

        return Blank(masked, quote + 1, EscapedLiteralEnd(source, quote + 1, '"')) + 1;
    }

    // The offset of the closing delimiter of a literal where a backslash escapes the next
    // character. A regular literal cannot span lines, so a newline also ends it.
    private static int EscapedLiteralEnd(string source, int from, char delimiter)
    {
        int k = from;
        while (k < source.Length && source[k] != delimiter && source[k] != '\n')
        {
            k += source[k] == '\\' ? 2 : 1;
        }

        return Math.Min(k, source.Length);
    }

    // Blanks [from, to) except line breaks, and returns to.
    private static int Blank(char[] masked, int from, int to)
    {
        for (int k = from; k < to; k++)
        {
            if (masked[k] is not ('\n' or '\r'))
            {
                masked[k] = ' ';
            }
        }

        return to;
    }

    /// <summary>
    /// The scanner itself. The fixture tests and the tree test both run it, so both exercise one
    /// code path. Returns the 1-based line of each bare snapshot event.
    /// </summary>
    private static List<int> FindBareSnapshotEvents(string source)
    {
        string code = Mask(source);

        List<(int Start, int End)> invokeCalls =
            [.. InvokeCall.Matches(code).Select(m => (m.Index, MatchingParen(code, m.Index + m.Length - 1)))];

        // A Select whose argument is itself a lambda is LINQ. A lambda cannot convert to EventArgs.
        List<int> eventCalls = [.. EventCall.Matches(code)
            .Where(m => m.Groups["name"].Value != "Select" || !ArgumentIsALambda(code, m.Index + m.Length))
            .Select(m => m.Index)];

        HashSet<int> reportedStatementEnds = [];
        List<int> lines = [];

        foreach (Match lookup in Lookup.Matches(code))
        {
            int statementEnd = StatementEnd(code, lookup.Index);
            List<int> events = [.. eventCalls.Where(e => e >= lookup.Index && e < statementEnd)];

            if (events.Count == 0)
            {
                continue;
            }

            // The lookup and every event must sit inside one InvokeAsync call. An InvokeAsync that
            // only returns the snapshot still fires the event on the test thread.
            if (invokeCalls.Any(call => Encloses(call, lookup.Index) && events.All(e => Encloses(call, e))))
            {
                continue;
            }

            if (reportedStatementEnds.Add(statementEnd))
            {
                lines.Add(code.AsSpan(0, lookup.Index).Count('\n') + 1);
            }
        }

        return lines;
    }

    private static bool Encloses((int Start, int End) call, int position) =>
        call.Start < position && call.End > position;

    // The change in depth at one character, counting every kind of bracket.
    private static int Delta(char c) => c is '(' or '[' or '{' ? 1 : c is ')' or ']' or '}' ? -1 : 0;

    // The first semicolon at depth zero or less. A semicolon inside a block lambda in the chain sits
    // deeper and does not end the statement. A closer of an enclosing call does not end it either.
    private static int StatementEnd(string code, int start)
    {
        int depth = 0;
        for (int k = start; k < code.Length; k++)
        {
            char c = code[k];
            depth += Delta(c);
            if (c == ';' && depth <= 0)
            {
                return k;
            }
        }

        return code.Length;
    }

    // The matching ) of the ( at openIndex, counting parens only.
    private static int MatchingParen(string code, int openIndex)
    {
        int depth = 0;
        for (int k = openIndex; k < code.Length; k++)
        {
            depth += code[k] == '(' ? 1 : code[k] == ')' ? -1 : 0;
            if (depth == 0)
            {
                return k;
            }
        }

        return code.Length;
    }

    // True when the argument list that starts at from holds => at depth zero. A deeper =>, inside
    // an argument that can still be an EventArgs, does not count.
    private static bool ArgumentIsALambda(string code, int from)
    {
        int depth = 0;
        for (int k = from; k < code.Length; k++)
        {
            char c = code[k];
            depth += Delta(c);
            if (depth < 0)
            {
                return false;
            }

            if (depth == 0 && c == '=' && k + 1 < code.Length && code[k + 1] == '>')
            {
                return true;
            }
        }

        return false;
    }

    [Theory]
    [InlineData("cut.FindAll(\"input\")[0].Change(true);", 1)]
    [InlineData("await cut.FindAll(\"button\")[0].ClickAsync(new MouseEventArgs());", 1)]
    [InlineData("page.FindAll(\".pager button\")\n    .Single(b => b.TextContent == \"2\")\n    .Click();", 1)]
    [InlineData("cut.FindAll<IHtmlInputElement>(\"input\")[0].Change(true);", 1)]
    [InlineData("cut.Find(\"ul\").QuerySelector(\"button\")!.Click();", 1)]
    [InlineData("cut.Find(\"ul\").QuerySelectorAll(\"button\")[1].Click();", 1)]
    [InlineData("cut.Find(\"span\").Closest(\"button\")!.Click();", 1)]
    [InlineData("cut.Find(\"ul\").Children[0].Click();", 1)]
    [InlineData("cut.Find(\"span\").ParentElement!.Click();", 1)]
    [InlineData("cut.Find(\"li\").NextElementSibling!.Click();", 1)]
    [InlineData("cut.Find(\"li\").PreviousElementSibling!.Click();", 1)]
    [InlineData("cut.FindAll(\"button\")[0].TriggerEvent(\"onclick\", EventArgs.Empty);", 1)]
    [InlineData("await cut.InvokeAsync(() => cut.FindAll(\"a\")[0].Click());\ncut.FindAll(\"b\")[0].Click();", 2)]
    // The lookup runs on the renderer, but the event fires on the test thread.
    [InlineData("(await cut.InvokeAsync(() => cut.FindAll(\"button\")))[0].Click();", 1)]
    // A semicolon inside a block lambda in the chain must not end the statement.
    [InlineData("cut.FindAll(\"button\")\n    .Single(b => { return b.TextContent == \"2\"; })\n    .Click();", 1)]
    // A paren, a quote or a semicolon inside a literal must not move a boundary.
    [InlineData("await cut.InvokeAsync(() => cut.Find(\"a:not(\").Click());\ncut.FindAll(\"b\")[0].Click();", 2)]
    [InlineData("await cut.InvokeAsync(() => Use('('));\ncut.FindAll(\"b\")[0].Click();", 2)]
    [InlineData("cut.FindAll(\"a;b\")[0].Click();", 1)]
    [InlineData("cut.FindAll(\"a\\\"b\")[0].Click();", 1)]
    [InlineData("string p = @\"C:\\\";\ncut.FindAll(\"b\")[0].Click();", 2)]
    // The bUnit Select event: no argument, or an EventArgs argument.
    [InlineData("cut.FindAll(\"input\")[0].Select();", 1)]
    [InlineData("cut.FindAll(\"input\")[0].Select(new EventArgs());", 1)]
    [InlineData("await cut.FindAll(\"input\")[0].SelectAsync();", 1)]
    // A lambda nested inside an EventArgs argument does not make the call LINQ.
    [InlineData("cut.FindAll(\"input\")[0]\n    .Select(new[] { EventArgs.Empty }.Select(e => e).Single());", 1)]
    // Deliberately loud: a LINQ Select with a method group reads as the event.
    [InlineData("cut.FindAll(\"li\").Select(Describe).Should().HaveCount(2);", 1)]
    public void FindBareSnapshotEvents_EventOnASnapshotOutsideTheRenderer_ReportsItsLine(string source, int line) =>
        FindBareSnapshotEvents(source).Should().Equal(line);

    [Theory]
    [InlineData("await cut.InvokeAsync(() => cut.FindAll(\"button\")[0].Click());")]
    [InlineData("await cut.InvokeAsync(() =>\n{\n    cut.FindAll(\"button\")[0].Click();\n});")]
    [InlineData("await cut.InvokeAsync(() => cut.FindAll(\"button\")\n    .Single(b => { return b.TextContent == \"2\"; })\n    .Click());")]
    [InlineData("cut.FindAll(\"li\").Select((e, i) => e.TextContent + i).Should().HaveCount(2);")]
    [InlineData("cut.Find(\"button\").Click();")]
    [InlineData("cut.FindAll(\"li\").Select(e => e.TextContent).Should().Equal(\"a\", \"b\");")]
    [InlineData("cut.WaitForAssertion(() => cut.FindAll(\"input\").Count.Should().Be(2));")]
    [InlineData("// cut.FindAll(\"button\")[0].Click();")]
    [InlineData("cut.Find(\"x\").Click(); // then cut.FindAll(\"b\")[0].Click();")]
    [InlineData("/* cut.FindAll(\"b\")[0].Click(); */")]
    [InlineData("string s = \"cut.FindAll(b)[0].Click();\";")]
    public void FindBareSnapshotEvents_SafeForm_ReportsNothing(string source) =>
        FindBareSnapshotEvents(source).Should().BeEmpty();

    [Fact]
    public void FindBareSnapshotEvents_PatternInsideARawString_ReportsNothing()
    {
        string source = """"
            string s = """
                cut.FindAll("b")[0].Click();
                """;
            """";

        FindBareSnapshotEvents(source).Should().BeEmpty();
    }

    [Fact]
    public void EventMethodNames_ReadFromBunit_HoldTheCommonEvents() =>
        EventMethodNames.Should().Contain(["Click", "ClickAsync", "Change", "Input", "Select", "SelectAsync"]);

    [Fact]
    public void UiTestSources_FireNoEventOnASnapshotOutsideTheRenderer()
    {
        string root = ProjectRoot();

        // Forward slashes, because CI runs the .NET tests on Linux.
        List<string> files = [.. Directory.EnumerateFiles(root, "*.cs", SearchOption.AllDirectories)
            .Select(file => Path.GetRelativePath(root, file).Replace('\\', '/'))
            .Where(path => path.Split('/')[0] is not ("bin" or "obj"))
            .Where(path => path != "SnapshotEventGuardTests.cs")];

        files.Should().Contain("Pages/ProfilesPageTests.cs",
            "the scan must read this project's own test sources, or it passes with nothing checked");

        List<string> findings = [.. files.SelectMany(path =>
            FindBareSnapshotEvents(File.ReadAllText(Path.Combine(root, path))).Select(line => $"{path}:{line}"))];

        findings.Should().BeEmpty(
            "an event on a FindAll element or a child lookup must run inside InvokeAsync, together with "
            + "the lookup. See the bUnit rule in src/Frontend/AHKFlowApp.UI.Blazor/CLAUDE.md. A LINQ Select "
            + "with a method group reads as the bUnit Select event, so write it as a lambda");
    }
}
