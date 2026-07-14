using System.Text;
using System.Text.RegularExpressions;
using AHKFlowApp.Application.DTOs;

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
/// <param name="DefinitionCount">Number of structural <c>:options:trigger::</c> lines outside any body (rule 2).</param>
/// <param name="BodyKind">Classified body shape (feeds the preview summary).</param>
/// <param name="BodyLineCount">Literal line count for a continuation body (0 for other shapes).</param>
/// <param name="HasDirectiveOutsideLiteralBody">A <c>#</c> directive line exists outside a literal continuation body (rule 5).</param>
/// <param name="Error">Structural error message (rule 1 / 6 / 7); null when <see cref="IsValid"/>.</param>
internal sealed record RawParseResult(
    bool IsValid,
    bool FirstLineValid,
    string Trigger,
    string[] OptionTokens,
    string[] UnknownOptionTokens,
    int DefinitionCount,
    RawBodyKind BodyKind,
    int BodyLineCount,
    bool HasDirectiveOutsideLiteralBody,
    string? Error);

/// <summary>
/// Result of <see cref="RawHotstringDefinitionParser.Prepare"/> — the single authoritative
/// preparation of a pasted Raw definition that every caller (validator, Create/Update handlers,
/// preview) consumes.
/// </summary>
/// <param name="NormalizedDefinition">Body-aware normalized text with lifted comment lines removed — the exact text handlers persist.</param>
/// <param name="LiftedComment">Leading <c>;</c> comment lines joined with <c>\n</c> (marker stripped), moved into Description; null when none.</param>
/// <param name="Parsed">Structural parse of <see cref="NormalizedDefinition"/>.</param>
internal sealed record RawPrepared(string NormalizedDefinition, string? LiftedComment, RawParseResult Parsed);

/// <summary>
/// Parses an entire verbatim AHK v2 hotstring definition (first line
/// <c>:options:trigger::</c>, optional inline replacement, brace <c>{ … }</c> code body, or
/// literal <c>( … )</c> continuation section) into the structural facts the Raw validator and
/// handlers need. Sibling of <see cref="AhkHotstringParser"/> but intentionally simpler: no
/// Send-body conversion, no v1 rescue — it splits structure, tokenizes options, counts
/// definitions, and classifies the body.
///
/// Deliberately supports a restricted subset of AHK v2 (see <c>HotstringRules.AddRawKindRules</c>):
/// naive brace counting on brace bodies only, no string/comment lexing. Continuation sections are
/// accepted as verbatim literal text; OTB braces (<c>:X:t::{</c>) are accepted and normalized
/// (Task 2). Known option set is per the official v2 docs:
/// <see href="https://www.autohotkey.com/docs/v2/Hotstrings.htm"/>. Continuation sections per
/// <see href="https://www.autohotkey.com/docs/v2/Scripts.htm#continuation-section"/>.
/// </summary>
internal static partial class RawHotstringDefinitionParser
{
    private const string FirstLineError = "Not a valid hotstring definition — expected `:options:trigger::replacement`.";
    private const string BraceRequiredError = "Add a replacement after `::`, or put `{` (code) or `(` (multi-line text) on its own line below the trigger.";
    private const string UnbalancedError = "Raw definition must have balanced braces.";
    private const string ContentAfterBraceError = "Raw definition has content after the closing brace.";
    private const string ContentAfterInlineError = "Raw definition has content after the inline replacement.";
    private const string OpenerIsExpressionError = "A continuation section opener must contain only options after `(` — an extra `(` or `)` (outside the Join parameter) makes AutoHotkey read the line as an expression; put the closing `)` on its own line.";
    private const string UnclosedContinuationError = "Raw definition has an unclosed continuation section — add a closing `)` on its own line.";
    private const string ContentAfterCloseError = "Raw definition has content after the closing `)`.";

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
    /// Save-time normalization for a Raw definition — delegates to <see cref="Prepare"/> and
    /// returns just the persisted text. Callers that also need the lifted comment or parse facts
    /// should call <see cref="Prepare"/> directly (a single pass) rather than re-parsing.
    /// </summary>
    public static string Normalize(string rawDefinition) => Prepare(rawDefinition).NormalizedDefinition;

    /// <summary>
    /// One authoritative preparation pass for a pasted Raw definition: lift leading <c>;</c>
    /// comment lines into <see cref="RawPrepared.LiftedComment"/>, body-aware normalize the
    /// remainder, and parse it — so validation, save, and preview never disagree.
    /// </summary>
    public static RawPrepared Prepare(string rawDefinition)
    {
        ArgumentNullException.ThrowIfNull(rawDefinition);

        string[] rawLines = rawDefinition.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        (string? lifted, int defStartIdx) = LiftLeadingComments(rawLines);

        string definitionText = string.Join('\n', rawLines[defStartIdx..]);
        string normalized = NormalizeCore(definitionText);
        RawParseResult parsed = Parse(normalized);

        return new RawPrepared(normalized, lifted, parsed);
    }

    // Consume leading blank/comment lines above the first definition line. Comment lines (first
    // non-blank char ';') are joined with '\n' with the ';' + one following space stripped;
    // returns the joined comment (null when none) and the index of the first non-comment line.
    private static (string? Lifted, int DefStartIdx) LiftLeadingComments(string[] lines)
    {
        List<string> comments = [];
        int i = 0;
        for (; i < lines.Length; i++)
        {
            string trimmed = lines[i].TrimStart();
            if (trimmed.Length == 0)
                continue;
            if (trimmed.StartsWith(';'))
            {
                string rest = trimmed[1..];
                comments.Add((rest.StartsWith(' ') ? rest[1..] : rest).TrimEnd());
                continue;
            }

            break;
        }

        return comments.Count == 0 ? (null, 0) : (string.Join('\n', comments), i);
    }

    // Body-aware normalization: CRLF/lone-CR → LF, trims leading/trailing blank lines and per-line
    // trailing whitespace, and rewrites a genuine OTB brace (:X:t::{) to { on its own line below
    // the trigger. Lines between a continuation section's ( and ) are preserved byte-for-byte
    // (trailing spaces/tabs are significant under RTrim0); elsewhere AHK ignores literal trailing
    // whitespace on script lines (a meaningful trailing space needs the `s/`t escapes, untouched).
    private static string NormalizeCore(string definitionText)
    {
        (string[] lines, int firstIdx, Match? match, BodyClassification? body) = Analyze(definitionText);

        List<string> outLines = new(lines.Length + 1);
        for (int i = 0; i < lines.Length; i++)
        {
            // Expand a genuine OTB brace onto its own line below the trigger.
            if (body is { IsOtb: true } && i == firstIdx)
            {
                string defLine = lines[i];
                outLines.Add(defLine[..^match!.Groups[3].Value.Length].TrimEnd());
                outLines.Add("{");
                continue;
            }

            // Preserve continuation-body lines (strictly between "(" and ")") byte-for-byte.
            bool preserve = body is { Kind: RawBodyKind.Continuation }
                && i > body.BodyLineStart && i < body.BodyLineEnd;

            outLines.Add(preserve ? lines[i] : lines[i].TrimEnd());
        }

        int start = 0;
        while (start < outLines.Count && outLines[start].Length == 0)
            start++;

        int end = outLines.Count - 1;
        while (end >= start && outLines[end].Length == 0)
            end--;

        return start > end ? string.Empty : string.Join('\n', outLines.GetRange(start, end - start + 1));
    }

    public static RawParseResult Parse(string rawDefinition)
    {
        ArgumentNullException.ThrowIfNull(rawDefinition);

        (string[] lines, _, Match? match, BodyClassification? body) = Analyze(rawDefinition);
        if (match is null || body is null)
            return Invalid(FirstLineError);

        // No trimming: spaces/tabs are literal within an AHK abbreviation, and the raw text is
        // emitted verbatim, so the derived trigger must match it exactly (dedup, DB, UI display).
        string trigger = DecodeEscapes(match.Groups[2].Value);
        (string[] optionTokens, string[] unknownTokens) = TokenizeOptions(match.Groups[1].Value);

        // Body-aware structural facts across the whole paste (rules 2 and 5).
        (int definitionCount, bool directiveOutside) = ScanStructure(lines, body);

        return new RawParseResult(
            IsValid: body.Valid,
            FirstLineValid: true,
            Trigger: trigger,
            OptionTokens: optionTokens,
            UnknownOptionTokens: unknownTokens,
            DefinitionCount: definitionCount,
            BodyKind: body.Kind,
            BodyLineCount: body.BodyLineCount,
            HasDirectiveOutsideLiteralBody: directiveOutside,
            Error: body.Error);
    }

    // Shared structural pass used by both Parse and Normalize: LF-normalize, find the first
    // non-blank line, match it as a definition, and classify its body. Match/Body are null when
    // the first line is missing or not a valid definition.
    private static (string[] Lines, int FirstIdx, Match? Match, BodyClassification? Body) Analyze(string rawDefinition)
    {
        string[] lines = rawDefinition.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

        int firstIdx = FirstNonBlank(lines, 0);
        if (firstIdx < 0)
            return (lines, -1, null, null);

        Match match = HotstringLine().Match(lines[firstIdx]);
        if (!match.Success)
            return (lines, firstIdx, null, null);

        (string[] optionTokens, _) = TokenizeOptions(match.Groups[1].Value);
        BodyClassification body = ClassifyBody(optionTokens, match.Groups[3].Value, lines, firstIdx);
        return (lines, firstIdx, match, body);
    }

    private static RawParseResult Invalid(string error) =>
        new(IsValid: false, FirstLineValid: false, Trigger: "", OptionTokens: [],
            UnknownOptionTokens: [], DefinitionCount: 0, BodyKind: RawBodyKind.None,
            BodyLineCount: 0, HasDirectiveOutsideLiteralBody: false, Error: error);

    /// <summary>
    /// Classification of a definition's body, including the absolute line range it spans so the
    /// whole-paste structural scan can skip body interiors. <see cref="BodyLineStart"/>/
    /// <see cref="BodyLineEnd"/> are -1 when there is no multi-line body (inline / none).
    /// </summary>
    private sealed record BodyClassification(
        bool Valid,
        string? Error,
        RawBodyKind Kind,
        int BodyLineCount,
        int BodyLineStart,
        int BodyLineEnd,
        bool IsOtb = false);

    // Structural rules 6 and 7. An inline replacement forbids further lines and is not
    // brace-balance checked; a bare "::" first line requires a brace body or continuation section.
    private static BodyClassification ClassifyBody(string[] optionTokens, string inlineRest, string[] lines, int firstIdx)
    {
        // A whitespace-only inline rest is a bare trigger — normalization strips it, so classify
        // the following lines as the body (Normalize analyzes pre-normalization text).
        if (inlineRest.Trim().Length > 0)
        {
            // A lone trailing "{" is either an OTB brace-body opener or, when text/raw send-mode
            // is active, an inline literal replacement that types "{" (per the AHK brace rule).
            if (inlineRest.Trim() == "{" && !TextOrRawModeActive(optionTokens))
            {
                // OTB: validate the brace body from this "{" (depth 1) plus the trailing lines.
                string region = string.Join('\n', lines[(firstIdx + 1)..].Prepend("{"));
                (bool otbValid, string? otbError) = ScanBraceBody(region);
                int otbCloseIdx = FindBraceCloseLine(lines, firstIdx + 1, 1);
                return new(otbValid, otbError, RawBodyKind.Braces, 0, firstIdx + 1, otbCloseIdx, IsOtb: true);
            }

            // Real inline replacement — no further non-blank lines allowed.
            return HasNonBlank(lines, firstIdx + 1)
                ? new(false, ContentAfterInlineError, RawBodyKind.Inline, 0, -1, -1)
                : new(true, null, RawBodyKind.Inline, 0, -1, -1);
        }

        int bodyIdx = FirstNonBlank(lines, firstIdx + 1);
        if (bodyIdx < 0)
            return new(false, BraceRequiredError, RawBodyKind.None, 0, -1, -1);

        string opener = lines[bodyIdx];

        // Continuation section: opener's first non-blank character is '('.
        if (opener.TrimStart().StartsWith('('))
            return ClassifyContinuation(lines, bodyIdx);

        // Brace body: opener line is exactly "{".
        if (opener.Trim() == "{")
            return ClassifyBraces(lines, bodyIdx);

        return new(false, BraceRequiredError, RawBodyKind.None, 0, -1, -1);
    }

    // Continuation section: verbatim literal text between an opener line starting with '(' and a
    // closing line that is exactly ')'. The opener remainder (Join/LTrim/RTrim0/…) is unvalidated
    // pass-through, except an extra '(' or ')' to the right of the initial '(' (outside the Join
    // option's parameter) makes AHK read the line as an expression, not an opener (Scripts.htm).
    private static BodyClassification ClassifyContinuation(string[] lines, int openerIdx)
    {
        if (OpenerIsExpression(lines[openerIdx]))
            return new(false, OpenerIsExpressionError, RawBodyKind.None, 0, -1, -1);

        int closeIdx = -1;
        for (int i = openerIdx + 1; i < lines.Length; i++)
        {
            if (lines[i].Trim() == ")")
            {
                closeIdx = i;
                break;
            }
        }

        // Unclosed: still treat opener→EOF as the intended literal body so the whole-paste scan
        // skips it — otherwise interior "::x::y" or "#…" lines would trip the multiple-definition
        // or directive rules before this (more accurate) unclosed-section error surfaces.
        if (closeIdx < 0)
            return new(false, UnclosedContinuationError, RawBodyKind.Continuation,
                lines.Length - openerIdx - 1, openerIdx, lines.Length - 1);

        int bodyLineCount = closeIdx - openerIdx - 1;

        return HasNonBlank(lines, closeIdx + 1)
            ? new(false, ContentAfterCloseError, RawBodyKind.Continuation, bodyLineCount, openerIdx, closeIdx)
            : new(true, null, RawBodyKind.Continuation, bodyLineCount, openerIdx, closeIdx);
    }

    // AHK v2 (Scripts.htm): a line whose first non-blank char is '(' opens a continuation section
    // unless an extra '(' or ')' appears to its right — then it is reinterpreted as an expression.
    // Parentheses inside the Join option's parameter are exempt (e.g. `(Join)` joins lines with ')').
    // Options are whitespace-delimited; the Join parameter is the non-blank run right after "Join".
    private static bool OpenerIsExpression(string openerLine)
    {
        string rest = openerLine.TrimStart()[1..]; // drop the initial '('
        foreach (string token in rest.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
        {
            if (token.StartsWith("Join", StringComparison.OrdinalIgnoreCase))
                continue; // Join's parameter may legitimately carry '(' or ')'
            if (token.IndexOfAny(['(', ')']) >= 0)
                return true;
        }

        return false;
    }

    private static BodyClassification ClassifyBraces(string[] lines, int openerIdx)
    {
        (bool valid, string? error) = ScanBraceBody(string.Join('\n', lines[openerIdx..]));
        int closeIdx = FindBraceCloseLine(lines, openerIdx, 0);
        return new(valid, error, RawBodyKind.Braces, 0, openerIdx, closeIdx);
    }

    // Text/raw send-mode is active when the LAST of the mutually-exclusive T/R/T0/R0 option tokens
    // turns it on. T/R enable it, T0/R0 cancel it; last-wins (do not test "tokens contain T/R").
    private static bool TextOrRawModeActive(string[] optionTokens)
    {
        bool active = false;
        foreach (string token in optionTokens)
        {
            if (token.Equals("T", StringComparison.OrdinalIgnoreCase) || token.Equals("R", StringComparison.OrdinalIgnoreCase))
                active = true;
            else if (token.Equals("T0", StringComparison.OrdinalIgnoreCase) || token.Equals("R0", StringComparison.OrdinalIgnoreCase))
                active = false;
        }

        return active;
    }

    // Line index where naive brace depth returns to zero (the closing-brace line), starting from
    // <paramref name="initialDepth"/> (1 for an OTB "{" already consumed on the definition line).
    // Falls back to the last line when unbalanced; ScanBraceBody reports the validity error.
    private static int FindBraceCloseLine(string[] lines, int startIdx, int initialDepth)
    {
        int depth = initialDepth;
        for (int i = startIdx; i < lines.Length; i++)
        {
            foreach (char c in lines[i])
            {
                if (c == '{')
                {
                    depth++;
                }
                else if (c == '}')
                {
                    depth--;
                    if (depth == 0)
                        return i;
                }
            }
        }

        return lines.Length - 1;
    }

    // Whole-paste structural scan (rules 2 and 5), body-aware:
    // - continuation bodies are literal text → skipped entirely (no definition, no directive);
    // - brace bodies are code → interior lines are not counted as definitions, but a directive
    //   inside is still rejected (braces do not scope a directive's effect on later definitions).
    private static (int DefinitionCount, bool DirectiveOutsideLiteral) ScanStructure(string[] lines, BodyClassification body)
    {
        int definitionCount = 0;
        bool directive = false;

        for (int i = 0; i < lines.Length; i++)
        {
            bool inBody = body.BodyLineStart >= 0 && i >= body.BodyLineStart && i <= body.BodyLineEnd;

            if (inBody)
            {
                if (body.Kind == RawBodyKind.Braces && lines[i].TrimStart().StartsWith('#'))
                    directive = true;
                continue;
            }

            if (HotstringLine().IsMatch(lines[i]))
                definitionCount++;
            else if (lines[i].TrimStart().StartsWith('#'))
                directive = true;
        }

        return (definitionCount, directive);
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

    private static bool HasNonBlank(string[] lines, int from) => FirstNonBlank(lines, from) >= 0;

    private static int FirstNonBlank(string[] lines, int from)
    {
        for (int i = from; i < lines.Length; i++)
            if (lines[i].Trim().Length > 0)
                return i;
        return -1;
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
