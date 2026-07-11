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
/// it exists only to drive UI hints (the "Use Macro?" suggestion, toolbar insertion guards)
/// and chip rendering. An unrecognized <c>{{...}}</c> candidate is treated as plain text
/// rather than reported as an error; the backend remains the sole source of truth for
/// Macro validation.
///
/// Deliberately a small linear character scan, not regex-based. A regex rewrite was
/// evaluated (2026-07-10) and rejected: an alternation such as
/// <c>\{\{\{\{.*?\}\}\}\}|\{\{.*?\}\}</c> cannot reproduce the scanner's
/// resume-after-orphan-escape rule — e.g. <c>{{{{cursor}}</c> (escape opener with no
/// <c>}}}}</c> closer) must yield literal <c>{{</c> followed by a real cursor token, while
/// the regex consumes <c>{{{{cursor}}</c> as one unknown candidate and misses the token.
/// Patching that with lookaheads ends up longer and less clear than the scan, and any
/// divergence here desynchronizes the "Use Macro?" hint from backend validation.
/// </summary>
public static class MacroTokens
{
    /// <summary>
    /// True if <paramref name="text"/> contains at least one well-formed, unescaped known
    /// token. An escaped-literal <c>{{{{...}}}}</c> never counts, even when its unescaped
    /// content looks like a token name (e.g. <c>{{{{cursor}}}}</c> unescapes to the literal
    /// text <c>{{cursor}}</c>, which is not a real token).
    /// </summary>
    public static bool ContainsKnownToken(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return Scan(text).Any(segment => segment.Token is not null);
    }

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

        foreach (Segment segment in Scan(text))
        {
            if (segment.Token is { } kind)
            {
                FlushText(plain, pieces);
                pieces.Add(new MacroTextPiece.Token(kind));
            }
            else
            {
                plain.Append(segment.Text);
            }
        }

        FlushText(plain, pieces);
        return pieces;
    }

    /// <summary>
    /// Raw character index of the first real <c>{{cursor}}</c> token, or null when the text
    /// has none. Escaped literals never match. Drives the dialog toolbar guards (block a
    /// second cursor, block Enter/Tab insertion behind the cursor).
    /// </summary>
    public static int? CursorTokenStart(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        foreach (Segment segment in Scan(text))
        {
            if (segment.Token == MacroTokenKind.Cursor)
                return segment.Start;
        }

        return null;
    }

    /// <summary>One scanned stretch of the raw text: a token (Text empty) or literal text.</summary>
    private readonly record struct Segment(int Start, string Text, MacroTokenKind? Token);

    private static IEnumerable<Segment> Scan(string text)
    {
        int i = 0;
        int runStart = 0;

        while (i < text.Length)
        {
            if (!IsDoubleOpenBrace(text, i))
            {
                i++;
                continue;
            }

            if (IsEscapeOpen(text, i))
            {
                int closeAt = text.IndexOf("}}}}", i + 4, StringComparison.Ordinal);
                if (closeAt >= 0)
                {
                    if (i > runStart)
                        yield return new Segment(runStart, text[runStart..i], null);

                    yield return new Segment(i, $"{{{{{text[(i + 4)..closeAt]}}}}}", null);
                    i = closeAt + 4;
                    runStart = i;
                    continue;
                }

                // No "}}}}" closer anywhere ahead — only the leading "{{" is literal text;
                // resume right after it so a following "{{...}}" is still evaluated as a
                // token candidate.
                i += 2;
                continue;
            }

            int close = text.IndexOf("}}", i + 2, StringComparison.Ordinal);
            if (close < 0)
            {
                // No closing "}}" anywhere ahead — the "{{" stays literal text.
                i += 2;
                continue;
            }

            MacroTokenKind? kind = ResolveToken(text[(i + 2)..close]);
            if (kind is { } resolvedKind)
            {
                if (i > runStart)
                    yield return new Segment(runStart, text[runStart..i], null);

                yield return new Segment(i, "", resolvedKind);
                runStart = close + 2;
            }
            // Unrecognized "{{...}}" candidate — not the backend's job here, it stays part
            // of the surrounding literal run.

            i = close + 2;
        }

        if (text.Length > runStart)
            yield return new Segment(runStart, text[runStart..], null);
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
