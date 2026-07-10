using System.Text;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>The kind of macro token a <see cref="MacroTextPiece.Token"/> piece represents.</summary>
public enum MacroTokenKind
{
    /// <summary><c>{{cursor}}</c> — the caret placement marker.</summary>
    Cursor,

    /// <summary><c>{{key:Enter}}</c>.</summary>
    Enter,

    /// <summary><c>{{key:Tab}}</c>.</summary>
    Tab,
}

/// <summary>
/// A single piece of a split macro replacement string: either a run of plain text
/// (including unescaped <c>{{{{...}}}}</c> content) or a recognized token. Closed
/// hierarchy — the private constructor restricts derivation to the nested records below.
/// A Razor component can iterate a <see cref="MacroTokens.Split"/> result and render each
/// piece as either an inline text span (<see cref="Text"/>) or a chip (<see cref="Token"/>).
/// </summary>
public abstract record MacroTextPiece
{
    private MacroTextPiece() { }

    /// <summary>A run of plain text.</summary>
    public sealed record Text(string Value) : MacroTextPiece;

    /// <summary>A recognized macro token.</summary>
    public sealed record Token(MacroTokenKind Kind) : MacroTextPiece;
}

/// <summary>
/// Lightweight frontend mirror of the backend grammar in
/// <c>AHKFlowApp.Application.Services.MacroTokenParser</c>. Recognizes the same three real
/// tokens (<c>{{cursor}}</c>, <c>{{key:Enter}}</c>, <c>{{key:Tab}}</c> — case-insensitive
/// token names, no interior whitespace) and the <c>{{{{...}}}}</c> escaped-literal form
/// (any inner content terminated by the first <c>}}}}</c>, unescaped to literal
/// <c>{{...}}</c> text).
///
/// Unlike the backend parser, this helper never validates or rejects malformed input —
/// it exists only to drive UI hints (the "Use Macro?" suggestion) and chip rendering.
/// An unrecognized <c>{{...}}</c> candidate is treated as plain text rather than reported
/// as an error; the backend remains the sole source of truth for Macro validation.
///
/// Deliberately a small linear character scan, not regex-based, matching the backend's
/// rationale: a non-Singleline <c>\{\{.*?\}\}</c> would silently skip token candidates that
/// span a newline. Since this helper's worst-case failure is a missed suggestion or a chip
/// falling back to plain text (not a data-integrity issue), a regex-based rewrite would be
/// an acceptable simplification later if needed — this scan just keeps behavior aligned
/// with the backend today.
/// </summary>
public static class MacroTokens
{
    /// <summary>
    /// True if <paramref name="text"/> contains at least one well-formed, unescaped known
    /// token. An escaped-literal <c>{{{{...}}}}</c> never counts, even when its unescaped
    /// content looks like a token name (e.g. <c>{{{{cursor}}}}</c> unescapes to the literal
    /// text <c>{{cursor}}</c>, which is not a real token).
    /// </summary>
    public static bool ContainsKnownToken(string text) =>
        Split(text).Any(piece => piece is MacroTextPiece.Token);

    /// <summary>
    /// Splits <paramref name="text"/> into an ordered sequence of plain-text and token
    /// pieces for chip rendering. Escaped literals split out as a plain-text piece
    /// containing their unescaped content, never as a token piece.
    /// </summary>
    public static IReadOnlyList<MacroTextPiece> Split(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        List<MacroTextPiece> pieces = [];
        StringBuilder plain = new();
        int i = 0;

        while (i < text.Length)
        {
            if (!IsDoubleOpenBrace(text, i))
            {
                plain.Append(text[i]);
                i++;
                continue;
            }

            if (IsEscapeOpen(text, i))
            {
                int closeAt = text.IndexOf("}}}}", i + 4, StringComparison.Ordinal);
                if (closeAt >= 0)
                {
                    plain.Append("{{").Append(text, i + 4, closeAt - (i + 4)).Append("}}");
                    i = closeAt + 4;
                    continue;
                }

                // No "}}}}" closer anywhere ahead — only the leading "{{" is literal text;
                // resume right after it so a following "{{...}}" is still evaluated as a
                // token candidate.
                plain.Append("{{");
                i += 2;
                continue;
            }

            int close = text.IndexOf("}}", i + 2, StringComparison.Ordinal);
            if (close < 0)
            {
                // No closing "}}" anywhere ahead — treat the "{{" as literal text.
                plain.Append("{{");
                i += 2;
                continue;
            }

            string candidate = text[(i + 2)..close];
            MacroTokenKind? kind = ResolveToken(candidate);

            if (kind is { } resolvedKind)
            {
                FlushText(plain, pieces);
                pieces.Add(new MacroTextPiece.Token(resolvedKind));
            }
            else
            {
                // Unrecognized "{{...}}" candidate — not the backend's job here, keep it
                // as plain text rather than reporting an error.
                plain.Append(text, i, close + 2 - i);
            }

            i = close + 2;
        }

        FlushText(plain, pieces);
        return pieces;
    }

    private static bool IsDoubleOpenBrace(string s, int i) =>
        s[i] == '{' && i + 1 < s.Length && s[i + 1] == '{';

    private static bool IsEscapeOpen(string s, int i) =>
        i + 3 < s.Length && s[i + 2] == '{' && s[i + 3] == '{';

    // Exact (non-trimmed) comparisons are what make interior whitespace not count as a
    // known token — "{{ cursor }}" candidate is " cursor ", which matches none of these.
    private static MacroTokenKind? ResolveToken(string candidate) =>
        candidate switch
        {
            _ when candidate.Equals("cursor", StringComparison.OrdinalIgnoreCase) => MacroTokenKind.Cursor,
            _ when candidate.Equals("key:enter", StringComparison.OrdinalIgnoreCase) => MacroTokenKind.Enter,
            _ when candidate.Equals("key:tab", StringComparison.OrdinalIgnoreCase) => MacroTokenKind.Tab,
            _ => null,
        };

    private static void FlushText(StringBuilder plain, List<MacroTextPiece> pieces)
    {
        if (plain.Length == 0)
            return;

        pieces.Add(new MacroTextPiece.Text(plain.ToString()));
        plain.Clear();
    }
}
