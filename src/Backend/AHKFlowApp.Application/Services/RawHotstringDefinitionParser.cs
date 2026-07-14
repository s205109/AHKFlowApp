using System.Text;
using System.Text.RegularExpressions;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Outcome of <see cref="RawHotstringDefinitionParser.Parse"/>. Structural facts the Raw
/// validator (<c>HotstringRules.AddRawKindRules</c>) maps to per-rule messages, plus the
/// derived <see cref="Trigger"/> and option tokens the handlers and preview summary reuse.
/// </summary>
/// <param name="IsValid">First line valid <em>and</em> body structurally complete (no rule 6/7 error).</param>
/// <param name="FirstLineValid">First non-blank line matches <c>:options:trigger::</c> (rule 1).</param>
/// <param name="Trigger">Decoded trigger parsed from the first line (empty when <see cref="FirstLineValid"/> is false).</param>
/// <param name="OptionTokens">Every option token, verbatim, in first-line order (feeds the parsed summary).</param>
/// <param name="UnknownOptionTokens">Tokens not in the known AHK v2 set (rule 4).</param>
/// <param name="DefinitionCount">Number of <c>:options:trigger::</c> definition starts in the paste (rule 2).</param>
/// <param name="Error">Structural error message (rule 1 / 6 / 7); null when <see cref="IsValid"/>.</param>
internal sealed record RawParseResult(
    bool IsValid,
    bool FirstLineValid,
    string Trigger,
    string[] OptionTokens,
    string[] UnknownOptionTokens,
    int DefinitionCount,
    string? Error);

/// <summary>
/// Parses an entire verbatim AHK v2 hotstring definition (first line
/// <c>:options:trigger::</c>, optional inline replacement or brace body) into the structural
/// facts the Raw validator and handlers need. Sibling of <see cref="AhkHotstringParser"/> but
/// intentionally simpler: no Send-body conversion, no v1 rescue, no normalization — it only
/// splits structure, tokenizes options, and counts definitions.
///
/// Deliberately supports a restricted subset of AHK v2 (see <c>HotstringRules.AddRawKindRules</c>):
/// naive brace counting on brace bodies only, no string/comment/continuation-section lexing,
/// OTB braces and continuation sections rejected. Known option set is per the official v2 docs:
/// <see href="https://www.autohotkey.com/docs/v2/Hotstrings.htm"/>.
/// </summary>
internal static partial class RawHotstringDefinitionParser
{
    private const string FirstLineError = "Not a valid hotstring definition — expected `:options:trigger::replacement`.";
    private const string BraceRequiredError = "Put `{` on its own line below the trigger.";
    private const string UnbalancedError = "Raw definition must have balanced braces.";
    private const string ContentAfterBraceError = "Raw definition has content after the closing brace.";
    private const string ContentAfterInlineError = "Raw definition has content after the inline replacement.";

    // :options:trigger::replacement — options/trigger contain no ':'; the trigger is
    // non-greedy so the FIRST '::' delimits, leaving any inline replacement in group 3.
    [GeneratedRegex(@"^\s*:([^:\r\n]*):(.*?)::(.*)$")]
    private static partial Regex HotstringLine();

    // Static known-option set (case-insensitive); K<n> and P<n> handled by pattern below.
    private static readonly HashSet<string> KnownOptions = new(StringComparer.OrdinalIgnoreCase)
    {
        "*", "*0", "?", "?0", "B", "B0", "C", "C0", "C1",
        "O", "O0", "R", "R0", "S", "S0", "SI", "SP", "SE",
        "T", "T0", "X", "Z", "Z0",
    };

    [GeneratedRegex(@"^K-?\d+$", RegexOptions.IgnoreCase)]
    private static partial Regex KOption();

    [GeneratedRegex(@"^P\d+$", RegexOptions.IgnoreCase)]
    private static partial Regex POption();

    /// <summary>
    /// Save-time normalization for a Raw definition — the only mutation applied before persisting.
    /// CRLF/lone-CR → LF, trims leading/trailing blank lines and per-line trailing whitespace.
    /// Interior lines and indentation are preserved exactly. Behavior-neutral: AHK ignores literal
    /// trailing whitespace on script lines (a meaningful trailing space needs the <c>`s</c>/<c>`t</c>
    /// escapes, which survive the trim untouched).
    /// </summary>
    public static string Normalize(string rawDefinition)
    {
        ArgumentNullException.ThrowIfNull(rawDefinition);

        var lines = rawDefinition
            .Replace("\r\n", "\n")
            .Replace('\r', '\n')
            .Split('\n')
            .Select(l => l.TrimEnd())
            .ToList();

        int start = 0;
        while (start < lines.Count && lines[start].Length == 0)
            start++;

        int end = lines.Count - 1;
        while (end >= start && lines[end].Length == 0)
            end--;

        return start > end ? string.Empty : string.Join('\n', lines.GetRange(start, end - start + 1));
    }

    public static RawParseResult Parse(string rawDefinition)
    {
        ArgumentNullException.ThrowIfNull(rawDefinition);

        string[] lines = rawDefinition.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        int definitionCount = lines.Count(l => HotstringLine().IsMatch(l));

        int firstIdx = Array.FindIndex(lines, l => l.Trim().Length > 0);
        if (firstIdx < 0)
            return Invalid(FirstLineError, definitionCount);

        Match match = HotstringLine().Match(lines[firstIdx]);
        if (!match.Success)
            return Invalid(FirstLineError, definitionCount);

        // No trimming: spaces/tabs are literal within an AHK abbreviation, and the raw text is
        // emitted verbatim, so the derived trigger must match it exactly (dedup, DB, UI display).
        string trigger = DecodeEscapes(match.Groups[2].Value);
        (string[] optionTokens, string[] unknownTokens) = TokenizeOptions(match.Groups[1].Value);
        string inlineRest = match.Groups[3].Value;
        string[] trailing = lines[(firstIdx + 1)..];

        (bool bodyValid, string? bodyError) = ClassifyBody(inlineRest, trailing);

        return new RawParseResult(
            IsValid: bodyValid,
            FirstLineValid: true,
            Trigger: trigger,
            OptionTokens: optionTokens,
            UnknownOptionTokens: unknownTokens,
            DefinitionCount: definitionCount,
            Error: bodyError);
    }

    private static RawParseResult Invalid(string error, int definitionCount) =>
        new(IsValid: false, FirstLineValid: false, Trigger: "", OptionTokens: [],
            UnknownOptionTokens: [], DefinitionCount: definitionCount, Error: error);

    // Structural rules 6 and 7. An inline replacement forbids further lines and is not
    // brace-balance checked; a bare "::" first line requires a "{" brace body on its own line.
    private static (bool Valid, string? Error) ClassifyBody(string inlineRest, string[] trailing)
    {
        if (inlineRest.Length > 0)
        {
            // OTB: "{" placed on the definition line — rejected (rule 7).
            if (inlineRest.Trim() == "{")
                return (false, BraceRequiredError);

            // Real inline replacement — no further non-blank lines allowed.
            return trailing.Any(l => l.Trim().Length > 0)
                ? (false, ContentAfterInlineError)
                : (true, null);
        }

        int bodyIdx = Array.FindIndex(trailing, l => l.Trim().Length > 0);
        if (bodyIdx < 0 || trailing[bodyIdx].Trim() != "{")
            return (false, BraceRequiredError);

        return ScanBraceBody(string.Join('\n', trailing[bodyIdx..]));
    }

    // Naive brace balance (D12): counts '{'/'}' with no string-literal or comment awareness.
    private static (bool Valid, string? Error) ScanBraceBody(string region)
    {
        int depth = 0;
        int closedAt = -1;

        for (int k = 0; k < region.Length; k++)
        {
            switch (region[k])
            {
                case '{':
                    depth++;
                    break;
                case '}':
                    depth--;
                    if (depth < 0)
                        return (false, UnbalancedError);
                    if (depth == 0 && closedAt < 0)
                        closedAt = k;
                    break;
            }
        }

        if (depth != 0)
            return (false, UnbalancedError);

        return region[(closedAt + 1)..].Trim().Length > 0
            ? (false, ContentAfterBraceError)
            : (true, null);
    }

    // Longest-match tokenizer: SE/SP/SI before S, and each flag greedily absorbs its trailing
    // sign/digits (K-1, K1000, P9, C1, *0) so the whole token is classified against the known set.
    private static (string[] Tokens, string[] Unknown) TokenizeOptions(string options)
    {
        List<string> tokens = [];
        List<string> unknown = [];

        int i = 0;
        while (i < options.Length)
        {
            if (char.IsWhiteSpace(options[i]))
            {
                i++;
                continue;
            }

            int start = i;
            if (options[i] is 'S' or 's'
                && i + 1 < options.Length
                && options[i + 1] is 'I' or 'P' or 'E' or 'i' or 'p' or 'e')
            {
                i += 2; // SI / SP / SE
            }
            else
            {
                i++; // flag char
                if (options[start] is 'K' or 'k' && i < options.Length && options[i] == '-')
                    i++; // K sign
                while (i < options.Length && char.IsDigit(options[i]))
                    i++;
            }

            string token = options[start..i];
            tokens.Add(token);
            if (!IsKnownOption(token))
                unknown.Add(token);
        }

        return ([.. tokens], [.. unknown]);
    }

    private static bool IsKnownOption(string token) =>
        KnownOptions.Contains(token) || KOption().IsMatch(token) || POption().IsMatch(token);

    private static string DecodeEscapes(string value)
    {
        if (!value.Contains('`'))
            return value;

        StringBuilder sb = new(value.Length);
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            if (c != '`')
            {
                sb.Append(c);
                continue;
            }

            if (i + 1 >= value.Length)
                break;

            sb.Append(value[++i] switch
            {
                '`' => '`',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                's' => ' ',
                ';' => ';',
                var other => other,
            });
        }

        return sb.ToString();
    }
}
