using System.Text;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>Result of decomposing a Raw definition back into structured fields.</summary>
/// <param name="Trigger">Decoded trigger from the first line.</param>
/// <param name="Body">Inline replacement, or the brace/continuation-body content when the definition uses one.</param>
/// <param name="UnexpressibleOptions">
/// Option tokens the four structured checkboxes (<c>*</c>/<c>?</c>/<c>C</c>/<c>O</c>) can't
/// represent (e.g. <c>K1000</c>, <c>SE</c>) — surfaced in the "discard options?" confirmation.
/// </param>
/// <param name="LossyReasons">
/// Human-readable reasons the conversion loses information a structured kind can't hold — e.g. a
/// continuation section's options (<c>Join</c>, <c>RTrim0</c>) or significant trailing whitespace.
/// Empty when the conversion is clean; surfaced in the confirmation alongside discarded options.
/// </param>
/// <param name="LiftedComment">
/// Leading <c>;</c> comment lines above the definition, joined with <c>\n</c> (marker stripped) —
/// mirrors the server lift so the dialog can fold them into Description instead of dropping them.
/// Null when there is no leading comment.
/// </param>
public sealed record RawDecomposition(
    string Trigger,
    string Body,
    IReadOnlyList<string> UnexpressibleOptions,
    IReadOnlyList<string> LossyReasons,
    string? LiftedComment = null);

/// <summary>
/// Client-side Raw definition compose/decompose for the edit dialog's kind switching. <see cref="Compose"/>
/// mirrors the server's <c>ScriptToRawComposer.Compose</c> byte-for-byte (guarded by a shared-fixture
/// test); <see cref="Decompose"/> is best-effort — the server re-parses and validates on save.
/// </summary>
public static class RawDefinition
{
    private static readonly HashSet<string> ExpressibleOptions =
        new(StringComparer.OrdinalIgnoreCase) { "*", "?", "C", "O" };

    /// <summary>
    /// Composes a starting Raw definition from structured fields, matching the server's Script→Raw
    /// transform: brace body, options in <c>* ? C O</c> order, backtick-first trigger escaping.
    /// </summary>
    public static string Compose(
        string trigger,
        string replacement,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        bool isCaseSensitive,
        bool omitEndingCharacter)
    {
        string options = "";
        if (!isEndingCharacterRequired) options += "*";
        if (isTriggerInsideWord) options += "?";
        if (isCaseSensitive) options += "C";
        if (omitEndingCharacter && isEndingCharacterRequired) options += "O";

        return $":{options}:{Escape(trigger)}::\n{{\n{replacement}\n}}";
    }

    /// <summary>Best-effort decomposition of a Raw definition into trigger + body + lost options.</summary>
    public static RawDecomposition Decompose(string rawDefinition)
    {
        string[] lines = (rawDefinition ?? "").Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');

        // Lift leading ';' comment lines the same way the server does, so a commented definition
        // still parses (and the comment folds into Description rather than being treated as body).
        (string? lifted, int defStart) = LiftLeadingComments(lines);
        string remainder = string.Join('\n', lines[defStart..]);

        int firstIdx = Array.FindIndex(lines, defStart, l => l.Trim().Length > 0);
        if (firstIdx < 0)
            return new RawDecomposition("", "", [], [], lifted);

        string first = lines[firstIdx].TrimStart();
        // :options:trigger::rest — options/trigger contain no ':'; first '::' delimits.
        int firstColon = first.IndexOf(':');
        if (firstColon != 0)
            return new RawDecomposition("", remainder, [], [], lifted);

        int secondColon = first.IndexOf(':', 1);
        if (secondColon < 0)
            return new RawDecomposition("", remainder, [], [], lifted);

        string optionsBlock = first[1..secondColon];
        int doubleColon = first.IndexOf("::", secondColon + 1, StringComparison.Ordinal);
        if (doubleColon < 0)
            return new RawDecomposition("", remainder, [], [], lifted);

        string triggerRaw = first[(secondColon + 1)..doubleColon];
        string inlineRest = first[(doubleColon + 2)..];
        string[] optionTokens = [.. TokenizeOptions(optionsBlock)];

        string body;
        List<string> lossy = [];
        string inlineTrim = inlineRest.Trim();
        bool textOrRawMode = TextOrRawModeActive(optionTokens);

        if (inlineTrim.Length > 0 && (inlineTrim != "{" || textOrRawMode))
        {
            // Real inline replacement. With text/raw send-mode active a lone trailing "{" is a
            // literal replacement (it types "{"), not an OTB brace-body opener.
            body = inlineRest;
        }
        else if (inlineTrim == "{")
        {
            // OTB: the "{" opens the brace body on the trigger line, so the body is the following
            // lines up to the last "}" (there is no separate "{" opener line to skip).
            string[] rest = lines[(firstIdx + 1)..];
            int close = Array.FindLastIndex(rest, l => l.Trim() == "}");
            body = close >= 0 ? string.Join('\n', rest[..close]) : string.Join('\n', rest).Trim();
        }
        else
        {
            string[] rest = lines[(firstIdx + 1)..];
            int bodyIdx = Array.FindIndex(rest, l => l.Trim().Length > 0);

            if (bodyIdx >= 0 && rest[bodyIdx].TrimStart().StartsWith('('))
            {
                // Continuation section: literal text strictly between the "(" and ")" lines.
                int close = Array.FindIndex(rest, bodyIdx + 1, l => l.Trim() == ")");
                string[] bodyLines = close > bodyIdx ? rest[(bodyIdx + 1)..close] : rest[(bodyIdx + 1)..];
                body = string.Join('\n', bodyLines);

                // Structured Text can't hold continuation options or significant trailing whitespace.
                string openerOptions = rest[bodyIdx].TrimStart()[1..].Trim();
                if (openerOptions.Length > 0)
                    lossy.Add($"continuation options `{openerOptions}`");
                if (bodyLines.Any(l => l.Length != l.TrimEnd().Length))
                    lossy.Add("significant trailing whitespace");
            }
            else
            {
                // Brace body: content strictly between the "{" line and the last "}" line.
                int open = Array.FindIndex(rest, l => l.Trim() == "{");
                int close = Array.FindLastIndex(rest, l => l.Trim() == "}");
                body = open >= 0 && close > open
                    ? string.Join('\n', rest[(open + 1)..close])
                    : string.Join('\n', rest).Trim();
            }
        }

        List<string> unexpressible = [.. optionTokens.Where(t => !ExpressibleOptions.Contains(t))];
        // No trimming: mirror the server parser — the abbreviation's whitespace is literal.
        return new RawDecomposition(DecodeEscapes(triggerRaw), body, unexpressible, lossy, lifted);
    }

    // Consume leading blank/comment lines above the definition (mirrors the server's lift): comment
    // lines (first non-blank char ';') join with '\n' with the ';' + one following space stripped.
    // Returns the joined comment (null when none) and the index of the first non-comment line.
    private static (string? Lifted, int DefStart) LiftLeadingComments(string[] lines)
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

    // Text/raw send-mode is active when the LAST of the mutually-exclusive T/R/T0/R0 option tokens
    // turns it on (T/R enable, T0/R0 cancel) — mirrors the server's TextOrRawModeActive.
    private static bool TextOrRawModeActive(IReadOnlyList<string> optionTokens)
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

    // Longest-match tokenizer (SE/SP/SI before S; each flag absorbs its sign/digits), mirroring the
    // server parser closely enough to identify which options the structured fields can't express.
    private static IEnumerable<string> TokenizeOptions(string options)
    {
        int i = 0;
        while (i < options.Length)
        {
            if (char.IsWhiteSpace(options[i])) { i++; continue; }

            int start = i;
            if (options[i] is 'S' or 's'
                && i + 1 < options.Length
                && options[i + 1] is 'I' or 'P' or 'E' or 'i' or 'p' or 'e')
            {
                i += 2;
            }
            else
            {
                i++;
                if (options[start] is 'K' or 'k' && i < options.Length && options[i] == '-') i++;
                while (i < options.Length && char.IsDigit(options[i])) i++;
            }

            yield return options[start..i];
        }
    }

    private static string Escape(string value) =>
        value
            .Replace("`", "``")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t")
            .Replace(";", "`;");

    private static string DecodeEscapes(string value)
    {
        if (!value.Contains('`')) return value;

        StringBuilder sb = new(value.Length);
        for (int i = 0; i < value.Length; i++)
        {
            char c = value[i];
            if (c != '`') { sb.Append(c); continue; }
            if (i + 1 >= value.Length) break;
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
