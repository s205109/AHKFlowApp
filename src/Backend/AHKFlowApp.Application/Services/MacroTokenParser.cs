using System.Text;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// A single lexical unit produced by <see cref="MacroTokenParser"/>: a run of literal text,
/// a key-press token, or the caret placement marker. Closed hierarchy — the private
/// constructor restricts derivation to the nested records below.
/// </summary>
internal abstract record MacroToken
{
    private MacroToken() { }

    /// <summary>A run of literal text emitted verbatim (includes unescaped <c>{{{{...}}}}</c> content).</summary>
    internal sealed record TextRun(string Text) : MacroToken;

    /// <summary>A key-press token. <see cref="Name"/> is canonical casing ("Enter" or "Tab").</summary>
    internal sealed record Key(string Name) : MacroToken;

    /// <summary>The caret placement marker (<c>{{cursor}}</c>).</summary>
    internal sealed record Cursor : MacroToken;
}

/// <summary>
/// Outcome of <see cref="MacroTokenParser.Parse"/>: the recognized token stream plus any
/// strict parse errors. Consumers (validator, emitter) treat a non-empty <see cref="Errors"/>
/// list as "this Replacement is not a valid Macro" regardless of what partial tokens exist.
/// </summary>
internal sealed record MacroParseResult(IReadOnlyList<MacroToken> Tokens, IReadOnlyList<string> Errors);

/// <summary>
/// Lexes a Macro hotstring's Replacement text into a stream of <see cref="MacroToken"/>s.
/// Recognizes <c>{{cursor}}</c>, <c>{{key:Enter}}</c>, <c>{{key:Tab}}</c> (case-insensitive
/// token names, no interior whitespace) and the <c>{{{{...}}}}</c> escaped-literal form — any
/// inner content, including whitespace/newlines, terminated by the first <c>}}}}</c> — which
/// emits literal <c>{{...}}</c> text (decision 11).
///
/// Deliberately a small linear character-by-character scanner, not regex-based: a non-Singleline
/// <c>\{\{.*?\}\}</c> would silently skip token candidates that span a newline instead of
/// raising the strict error this parser must report for them.
/// </summary>
internal static class MacroTokenParser
{
    private const string AllowedTokensMessage = "Allowed: {{cursor}}, {{key:Enter}}, {{key:Tab}}.";

    public static MacroParseResult Parse(string replacement)
    {
        ArgumentNullException.ThrowIfNull(replacement);

        List<MacroToken> tokens = [];
        List<string> errors = [];
        StringBuilder text = new();
        int i = 0;

        while (i < replacement.Length)
        {
            if (!IsDoubleOpenBrace(replacement, i))
            {
                text.Append(replacement[i]);
                i++;
                continue;
            }

            if (IsEscapeOpen(replacement, i))
            {
                int closeAt = replacement.IndexOf("}}}}", i + 4, StringComparison.Ordinal);
                if (closeAt >= 0)
                {
                    text.Append("{{").Append(replacement, i + 4, closeAt - (i + 4)).Append("}}");
                    i = closeAt + 4;
                    continue;
                }

                // No "}}}}" closer anywhere ahead — only the leading "{{" is literal text;
                // resume scanning right after it, so a following "{{...}}" is still evaluated
                // as a real token candidate (and reports its own strict error if malformed).
                text.Append("{{");
                i += 2;
                continue;
            }

            int close = replacement.IndexOf("}}", i + 2, StringComparison.Ordinal);
            if (close < 0)
            {
                // No closing "}}" anywhere ahead — the "{{" is literal text; keep scanning.
                text.Append("{{");
                i += 2;
                continue;
            }

            string candidate = replacement[(i + 2)..close];
            string raw = replacement[i..(close + 2)];
            MacroToken? token = ResolveToken(candidate);

            if (token is not null)
            {
                FlushText(text, tokens);
                tokens.Add(token);
            }
            else
            {
                errors.Add($"Unknown token '{raw}'. {AllowedTokensMessage}");
            }

            i = close + 2;
        }

        FlushText(text, tokens);
        return new MacroParseResult(tokens, errors);
    }

    private static bool IsDoubleOpenBrace(string s, int i) =>
        s[i] == '{' && i + 1 < s.Length && s[i + 1] == '{';

    private static bool IsEscapeOpen(string s, int i) =>
        i + 3 < s.Length && s[i + 2] == '{' && s[i + 3] == '{';

    // Exact (non-trimmed) comparisons are what make interior whitespace a strict error —
    // "{{ cursor }}" candidate is " cursor ", which matches none of these.
    private static MacroToken? ResolveToken(string candidate) =>
        candidate switch
        {
            _ when candidate.Equals("cursor", StringComparison.OrdinalIgnoreCase) => new MacroToken.Cursor(),
            _ when candidate.Equals("key:enter", StringComparison.OrdinalIgnoreCase) => new MacroToken.Key("Enter"),
            _ when candidate.Equals("key:tab", StringComparison.OrdinalIgnoreCase) => new MacroToken.Key("Tab"),
            _ => null,
        };

    private static void FlushText(StringBuilder text, List<MacroToken> tokens)
    {
        if (text.Length == 0)
            return;

        tokens.Add(new MacroToken.TextRun(text.ToString()));
        text.Clear();
    }
}
