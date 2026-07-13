using System.Text;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>Result of decomposing a Raw definition back into structured fields.</summary>
/// <param name="Trigger">Decoded trigger from the first line.</param>
/// <param name="Body">Inline replacement, or the brace-body content when the definition uses one.</param>
/// <param name="UnexpressibleOptions">
/// Option tokens the four structured checkboxes (<c>*</c>/<c>?</c>/<c>C</c>/<c>O</c>) can't
/// represent (e.g. <c>K1000</c>, <c>SE</c>) — surfaced in the "discard options?" confirmation.
/// </param>
public sealed record RawDecomposition(string Trigger, string Body, IReadOnlyList<string> UnexpressibleOptions);

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
        int firstIdx = Array.FindIndex(lines, l => l.Trim().Length > 0);
        if (firstIdx < 0)
            return new RawDecomposition("", "", []);

        string first = lines[firstIdx].TrimStart();
        // :options:trigger::rest — options/trigger contain no ':'; first '::' delimits.
        int firstColon = first.IndexOf(':');
        if (firstColon != 0)
            return new RawDecomposition("", rawDefinition ?? "", []);

        int secondColon = first.IndexOf(':', 1);
        if (secondColon < 0)
            return new RawDecomposition("", rawDefinition ?? "", []);

        string optionsBlock = first[1..secondColon];
        int doubleColon = first.IndexOf("::", secondColon + 1, StringComparison.Ordinal);
        if (doubleColon < 0)
            return new RawDecomposition("", rawDefinition ?? "", []);

        string triggerRaw = first[(secondColon + 1)..doubleColon];
        string inlineRest = first[(doubleColon + 2)..];

        string body;
        string inlineTrim = inlineRest.Trim();
        if (inlineRest.Length > 0 && inlineTrim != "{")
        {
            body = inlineRest;
        }
        else
        {
            // Brace body: content strictly between the "{" line and the last "}" line.
            string[] rest = lines[(firstIdx + 1)..];
            int open = Array.FindIndex(rest, l => l.Trim() == "{");
            int close = Array.FindLastIndex(rest, l => l.Trim() == "}");
            body = open >= 0 && close > open
                ? string.Join('\n', rest[(open + 1)..close])
                : string.Join('\n', rest).Trim();
        }

        List<string> unexpressible = [.. TokenizeOptions(optionsBlock).Where(t => !ExpressibleOptions.Contains(t))];
        return new RawDecomposition(DecodeEscapes(triggerRaw).Trim(), body, unexpressible);
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
