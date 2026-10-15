using System.Text;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// One piece of a split changelog entry: plain text, a code span, or a strong span. Closed
/// hierarchy — the private constructor restricts derivation to the nested records below.
/// </summary>
public abstract record ChangelogTextPiece
{
    private ChangelogTextPiece() { }

    /// <summary>Plain text, shown as written.</summary>
    public sealed record Text(string Value) : ChangelogTextPiece;

    /// <summary>The text between a pair of backticks.</summary>
    public sealed record Code(string Value) : ChangelogTextPiece;

    /// <summary>The text between a pair of <c>**</c> markers.</summary>
    public sealed record Strong(string Value) : ChangelogTextPiece;
}

/// <summary>
/// Splits one <c>CHANGELOG.md</c> entry into the two markdown spans that file uses: code spans
/// and <c>**</c> strong spans (backlog 176). It never builds markup. The Changelog page writes
/// every piece as text inside an element, so Blazor escapes it.
///
/// The rules are deliberately smaller than CommonMark, and they work on runs: a run is every
/// copy of the same marker character in a row. A run of exactly one backtick opens a code span,
/// and a run of exactly two <c>*</c> opens a strong span. The span closes at the next run of the
/// same length, so a span is never empty, and <c>**</c> inside a code span is code. Any other run,
/// or an opener with no closer, is text, and the scan consumes the whole run. So a rejected run
/// never lends its last marker to a later span. A strong span holds plain text, so a backtick
/// inside it stays visible.
/// </summary>
public static class ChangelogText
{
    public static IReadOnlyList<ChangelogTextPiece> Split(string text)
    {
        ArgumentNullException.ThrowIfNull(text);

        List<ChangelogTextPiece> pieces = [];
        StringBuilder plain = new();
        int i = 0;

        while (i < text.Length)
        {
            char marker = text[i];
            if (marker is not ('`' or '*'))
            {
                plain.Append(marker);
                i++;
                continue;
            }

            int runLength = RunLength(text, i);
            int openLength = marker == '`' ? 1 : 2;
            int closeAt = runLength == openLength ? FindRun(text, i + runLength, marker, openLength) : -1;
            if (closeAt < 0)
            {
                plain.Append(text, i, runLength);
                i += runLength;
                continue;
            }

            FlushText(plain, pieces);
            string content = text[(i + openLength)..closeAt];
            ChangelogTextPiece piece = marker == '`'
                ? new ChangelogTextPiece.Code(content)
                : new ChangelogTextPiece.Strong(content);
            pieces.Add(piece);
            i = closeAt + openLength;
        }

        FlushText(plain, pieces);
        return pieces;
    }

    /// <summary>How many copies of the character at <paramref name="start"/> follow in a row, itself included.</summary>
    private static int RunLength(string text, int start)
    {
        int end = start;
        while (end < text.Length && text[end] == text[start])
            end++;

        return end - start;
    }

    /// <summary>
    /// The start of the first run of exactly <paramref name="length"/> copies of
    /// <paramref name="marker"/> at <paramref name="from"/> or later, or -1. A run of another
    /// length is skipped whole.
    /// </summary>
    private static int FindRun(string text, int from, char marker, int length)
    {
        int i = from;
        while (i < text.Length)
        {
            if (text[i] != marker)
            {
                i++;
                continue;
            }

            int runLength = RunLength(text, i);
            if (runLength == length)
                return i;

            i += runLength;
        }

        return -1;
    }

    private static void FlushText(StringBuilder plain, List<ChangelogTextPiece> pieces)
    {
        if (plain.Length == 0)
            return;

        pieces.Add(new ChangelogTextPiece.Text(plain.ToString()));
        plain.Clear();
    }
}
