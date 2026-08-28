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
    // vk/sc codes) or one single-character key, then an optional "& Key" custom combination, then
    // an optional "Up" suffix, then "::". Leading indentation is ignored (AHK ignores it too).
    //
    // The single-character branch is any non-whitespace character, not a fixed punctuation list:
    // AHK v2 (KeyList.htm, "Keyboard") says "any single character can be used as a key name", so a
    // symbol or a non-ASCII letter such as "é" is a real key. Matching too widely only costs a
    // rejected body, and a line carrying "::" outside a string or a comment is not valid AHK v2
    // code in the first place — the multi-character branch is tried first, so "a & b::" still
    // parses as a custom combination rather than eating the "&".
    [GeneratedRegex(@"^[ \t]*[~*$!^+#<>]*(?:[A-Za-z0-9_]+|\S)(?:[ \t]*&[ \t]*[~*$!^+#<>]*(?:[A-Za-z0-9_]+|\S))?(?:[ \t]+[Uu][Pp])?[ \t]*::")]
    private static partial Regex HotkeyDefinitionLine();

    // Character-level state for the single-pass scan of one line. BlockComment is the only state
    // that carries across a line boundary — none of AHK's line-comment/string/quote shapes span a
    // newline, so every other state resets when a new line starts.
    private enum LexState
    {
        Code,
        LineComment,
        BlockComment,
        SingleQuoteString,
        DoubleQuoteString,
    }

    /// <summary>
    /// Returns the 1-based line number of the first line that opens a new top-level hotkey or
    /// hotstring definition, or null when the body opens none.
    /// </summary>
    public static int? FindInjectedDefinitionLine(string body)
    {
        ArgumentNullException.ThrowIfNull(body);

        string text = body.Replace("\r\n", "\n").Replace('\r', '\n');
        int length = text.Length;

        int depth = 0;
        bool inBlockComment = false;
        bool inContinuation = false;
        int lineIndex = 0;
        int pos = 0;

        while (true)
        {
            int newline = text.IndexOf('\n', pos);
            bool isLastLine = newline < 0;
            int lineEnd = isLastLine ? length : newline;

            if (inContinuation)
            {
                // AHK v2 (Scripts.htm): the section ends at the first line whose first non-blank
                // character is ")", and "any code after the closing parenthesis is also joined
                // with the other lines" — so the closing line is not required to be ")" alone.
                // A literal closing parenthesis is written "`)" and correctly fails this test.
                // The rest of the closing line belongs to the continued expression, never to a new
                // top-level definition, so it is neither scanned nor brace-counted.
                if (FirstNonBlankIs(text, pos, lineEnd, ')'))
                    inContinuation = false;
            }
            else
            {
                // No "not in a block comment" term: a line that lies wholly inside a block comment
                // strips to empty code and is filtered by the length test below, while a line that
                // closes the comment and then carries real code must stay a candidate.
                bool wasCandidate = lineIndex > 0 && depth == 0;
                (string code, bool stillInBlockComment, int braceDelta) = ScanLine(text, pos, lineEnd, inBlockComment);
                inBlockComment = stillInBlockComment;

                if (wasCandidate && code.TrimStart().Length > 0)
                {
                    if (RawHotstringDefinitionParser.IsDefinitionLine(code) || HotkeyDefinitionLine().IsMatch(code))
                        return lineIndex + 1;

                    // A candidate line that isn't a definition might still open a continuation
                    // section — check the original line (its trailing text after "(" is
                    // meaningless here either way).
                    if (RawHotstringDefinitionParser.IsContinuationOpener(text[pos..lineEnd]))
                        inContinuation = true;
                    else
                        depth += braceDelta;
                }
                else
                {
                    depth += braceDelta;
                }
            }

            if (isLastLine)
                break;

            pos = newline + 1;
            lineIndex++;
        }

        return null;
    }

    private static bool FirstNonBlankIs(string text, int start, int end, char target)
    {
        for (int i = start; i < end; i++)
        {
            if (char.IsWhiteSpace(text[i]))
                continue;
            return text[i] == target;
        }

        return false;
    }

    private static bool OnlyWhitespaceUntil(string text, int from, int end)
    {
        for (int i = from; i < end; i++)
            if (!char.IsWhiteSpace(text[i]))
                return false;

        return true;
    }

    // Single-pass character state machine for one line: strips line comments (';' at line start
    // or preceded by whitespace, outside a string), block comments ("/* ... */", which may open,
    // close, or continue across this line), and string contents (brace counting and the
    // definition regexes only need to see code, not string payloads) — all in one traversal, with
    // no recursion and no second pass to count braces. Returns the stripped code, whether a block
    // comment is still open at line end, and the net brace-depth delta contributed by this line.
    private static (string Code, bool StillInBlockComment, int BraceDelta) ScanLine(
        string text, int start, int end, bool startedInBlockComment)
    {
        StringBuilder code = new(end - start);
        int depth = 0;
        LexState state = startedInBlockComment ? LexState.BlockComment : LexState.Code;

        // Tracks whether real (non-whitespace) content has appeared since the current "segment"
        // began. A segment is the whole line normally, but resets at the point a block comment
        // closes mid-line — the remainder is treated exactly like a fresh line (matching what a
        // recursive re-strip of that remainder would see), which governs both the "/*" opener
        // test below (AHK v2, Language.htm: "/*" only opens a comment as the line's first token)
        // and the line-comment ";" test's "start of line" branch.
        bool sawNonBlank = false;
        int segmentStart = start;

        int i = start;
        while (i < end)
        {
            char c = text[i];

            switch (state)
            {
                case LexState.BlockComment:
                    // AHK v2 (Language.htm): "Excluding tabs and spaces, /* must appear at the
                    // start of the line, while */ can appear only at the start or end of a line."
                    // A closer with real code on both sides (neither start nor end) does not
                    // close it — the documented "Common mistake" example.
                    if (c == '*' && i + 1 < end && text[i + 1] == '/' && !sawNonBlank)
                    {
                        // Closer at the start: the comment ends there and the rest of the line is
                        // live code, so the remainder is scanned exactly as a fresh line would be.
                        state = LexState.Code;
                        i += 2;
                        segmentStart = i;
                        continue;
                    }

                    if (c == '*' && i + 1 < end && text[i + 1] == '/' && OnlyWhitespaceUntil(text, i + 2, end))
                    {
                        // Closer at the end: every character before it is still comment content,
                        // so this line contributes no code either way; the comment closes for the
                        // NEXT line only.
                        return (string.Empty, false, 0);
                    }

                    if (!char.IsWhiteSpace(c))
                        sawNonBlank = true;

                    i++;
                    continue;

                case LexState.LineComment:
                    i = end; // rest of the line is a line comment; nothing more counts
                    continue;

                case LexState.SingleQuoteString or LexState.DoubleQuoteString:
                    // AHK v2 accepts both single- and double-quoted strings (Language.htm): a
                    // string opened with one quote character closes only on the same character.
                    char quote = state == LexState.SingleQuoteString ? '\'' : '"';
                    if (c == '`' && i + 1 < end)
                    {
                        i += 2; // escaped character, skip both
                        continue;
                    }

                    if (c == quote)
                        state = LexState.Code;

                    i++;
                    continue;

                default: // LexState.Code
                    if (!sawNonBlank && c == '/' && i + 1 < end && text[i + 1] == '*')
                    {
                        state = LexState.BlockComment;
                        sawNonBlank = true;
                        i += 2;
                        continue;
                    }

                    if (c is '"' or '\'')
                    {
                        state = c == '"' ? LexState.DoubleQuoteString : LexState.SingleQuoteString;
                        sawNonBlank = true;
                        i++;
                        continue;
                    }

                    if (c == ';' && (i == segmentStart || char.IsWhiteSpace(text[i - 1])))
                    {
                        state = LexState.LineComment;
                        i = end;
                        continue;
                    }

                    if (c == '{')
                        depth++;
                    else if (c == '}')
                        depth--;

                    if (!char.IsWhiteSpace(c))
                        sawNonBlank = true;

                    code.Append(c);
                    i++;
                    continue;
            }
        }

        return (code.ToString(), state == LexState.BlockComment, depth);
    }
}
