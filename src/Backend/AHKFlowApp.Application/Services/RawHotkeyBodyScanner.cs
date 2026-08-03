using System.Text;
using System.Text.RegularExpressions;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Scans a Raw hotkey <c>Body</c> for a line that would open a new top-level hotkey or hotstring
/// definition once emitted verbatim after <c>key::</c> (<see cref="HotkeyEmitter"/>). Sibling of
/// <see cref="RawHotstringDefinitionParser"/>, which it reuses for the hotstring shape and the
/// continuation-section opener test.
/// </summary>
/// <remarks>
/// Deliberately not duplicate detection: it removes the injection itself, so a Raw body can never
/// introduce a duplicate combination (backlog 037). Unlike
/// <c>HotkeyRules.BracesBalanced</c>, which stays naive under decision D12, this scanner
/// tracks its own brace depth from code only — braces inside a string or a comment do not count,
/// or a line comment such as <c>; {</c> could hide an injected definition from the naive count.
/// The two checks are allowed to disagree; they answer different questions.
/// </remarks>
internal static partial class RawHotkeyBodyScanner
{
    // Prefix/modifier symbols, then a key name (letters/digits/underscore, i.e. named keys and
    // vk/sc codes) or one punctuation key, then an optional "& Key" custom combination, then an
    // optional "Up" suffix, then "::". Leading indentation is ignored (AHK ignores it too).
    [GeneratedRegex(@"^[ \t]*[~*$!^+#<>]*(?:[A-Za-z0-9_]+|[\[\];',./\\`=\-:<>])(?:[ \t]*&[ \t]*[~*$!^+#<>]*(?:[A-Za-z0-9_]+|[\[\];',./\\`=\-:<>]))?(?:[ \t]+[Uu][Pp])?[ \t]*::")]
    private static partial Regex HotkeyDefinitionLine();

    /// <summary>
    /// Returns the 1-based line number of the first line that opens a new top-level hotkey or
    /// hotstring definition, or null when the body opens none.
    /// </summary>
    public static int? FindInjectedDefinitionLine(string body)
    {
        ArgumentNullException.ThrowIfNull(body);

        string[] lines = body.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

        int depth = 0;
        bool inBlockComment = false;
        bool inContinuation = false;

        for (int i = 0; i < lines.Length; i++)
        {
            string line = lines[i];

            if (inContinuation)
            {
                if (line.Trim() == ")")
                    inContinuation = false;
                continue;
            }

            (string code, bool stillInBlockComment) = StripCommentsAndStrings(line, inBlockComment);
            bool wasCandidate = i > 0 && depth == 0 && !inBlockComment;
            inBlockComment = stillInBlockComment;

            if (wasCandidate && code.TrimStart().Length > 0)
            {
                if (RawHotstringDefinitionParser.IsDefinitionLine(code) || HotkeyDefinitionLine().IsMatch(code))
                    return i + 1;
            }

            // A candidate line that isn't a definition might still open a continuation section —
            // check the original line (its trailing text after "(" is meaningless here either way).
            if (wasCandidate && code.TrimStart().Length > 0
                && RawHotstringDefinitionParser.IsContinuationOpener(line))
            {
                inContinuation = true;
                continue;
            }

            depth += CountBraceDepth(code);
        }

        return null;
    }

    // Strips line comments (';' at line start or preceded by whitespace, outside a string) and
    // block comments ("/* ... */", which may open, close, or continue across this line) from
    // code-relevant content. String contents are dropped too — brace counting and the definition
    // regexes only need to see code, not string payloads. Returns the remaining code and whether a
    // block comment is still open at the end of the line.
    private static (string Code, bool StillInBlockComment) StripCommentsAndStrings(string line, bool startedInBlockComment)
    {
        if (startedInBlockComment)
        {
            // AHK v2 (Language.htm): "*/" closes a block comment when it appears at the start or
            // the end of a line — not only when the whole trimmed line is "*/". A closer with real
            // code on both sides (neither start nor end) does not close it (the documented
            // "Common mistake" example). Only the at-the-end case is implemented: any text before
            // the closer on this line is still comment content, so the line's own code is empty
            // either way. A closer at the start of the line, with code following it on that same
            // line, is not detected — a deliberate, narrow gap in the safe direction (a missed
            // rejection, not a false one), matching this scanner's error-toward-accepting stance.
            return line.TrimEnd().EndsWith("*/", StringComparison.Ordinal) ? ("", false) : ("", true);
        }

        string trimmed = line.TrimStart();
        if (trimmed.StartsWith("/*", StringComparison.Ordinal))
        {
            int afterOpen = line.IndexOf("/*", StringComparison.Ordinal) + 2;
            int closeAt = line.IndexOf("*/", afterOpen, StringComparison.Ordinal);
            return closeAt >= 0 ? ("", false) : ("", true);
        }

        // AHK v2 accepts both single- and double-quoted strings (Language.htm): a string opened
        // with one quote character closes only on the same character, so quoteChar tracks which.
        StringBuilder code = new(line.Length);
        char? quoteChar = null;
        for (int i = 0; i < line.Length; i++)
        {
            char c = line[i];

            if (quoteChar is char q)
            {
                if (c == '`' && i + 1 < line.Length)
                {
                    i++; // escaped character, skip both
                    continue;
                }

                if (c == q)
                    quoteChar = null;

                continue;
            }

            if (c is '"' or '\'')
            {
                quoteChar = c;
                continue;
            }

            if (c == ';' && (i == 0 || char.IsWhiteSpace(line[i - 1])))
                break; // rest of the line is a line comment

            code.Append(c);
        }

        return (code.ToString(), false);
    }

    private static int CountBraceDepth(string code)
    {
        int depth = 0;
        foreach (char c in code)
        {
            if (c == '{')
                depth++;
            else if (c == '}')
                depth--;
        }

        return depth;
    }
}
