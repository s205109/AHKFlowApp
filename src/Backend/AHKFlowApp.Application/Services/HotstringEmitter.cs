using System.Text;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotstring lines. Deterministic option order: X * ? C O T
/// — X leads for DateTime kind (T is never emitted for it); T trails for Text kind.
/// </summary>
internal static class HotstringEmitter
{
    public static string Emit(Hotstring hs) =>
        $":{BuildOptions(hs)}:{Escape(hs.Trigger)}::{BuildBody(hs)}";

    private static string BuildOptions(Hotstring hs)
    {
        bool isDateTime = hs.Kind == HotstringKind.DateTime;
        string options = isDateTime ? "X" : "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        if (hs.IsCaseSensitive) options += "C";
        if (hs.OmitEndingCharacter && hs.IsEndingCharacterRequired) options += "O"; // O is meaningless with *
        if (hs.Kind == HotstringKind.Text) options += "T"; // Text always emits literally (WYSIWYG) — D1. Brace-body kinds (DateTime/Macro/Script) have no auto-replace text and must never emit T.
        return options;
    }

    private static string BuildBody(Hotstring hs) =>
        hs.Kind switch
        {
            HotstringKind.DateTime => BuildDateTimeBody(hs),
            HotstringKind.Macro => BuildMacroBody(hs),
            _ => Escape(hs.Replacement),
        };

    private static string BuildDateTimeBody(Hotstring hs)
    {
        // DateTimeFormat is embedded raw (no escaping) because it has already passed a
        // server-side whitelist regex before reaching the emitter — validation lives elsewhere.
        string nowExpression = hs.DateOffsetAmount is int amount && hs.DateOffsetUnit is DateOffsetUnit unit
            ? $"DateAdd(A_Now, {amount}, \"{unit}\")"
            : "A_Now";
        return $"SendText(FormatTime({nowExpression}, \"{hs.DateTimeFormat}\"))";
    }

    // Assumes hs.Replacement has already passed Macro validation (parses cleanly, ≤1 cursor,
    // no keys after cursor) — that invariant is enforced elsewhere (Task 3), not re-checked here.
    // Produces a tab-indented AHK v2 brace body:
    //   {
    //   	SendText "..."
    //   	Send "{Enter N}"
    //   	Send "{Left N}"
    //   }
    // A Cursor token is transparent for SendText grouping (it emits no keystroke, so text
    // runs on either side of a bare cursor merge into one SendText call) — only a Key token
    // forces a break into a new statement. Consecutive identical Key tokens merge into one
    // "{Name N}" Send line; a differently-named Key starts a new line.
    private static string BuildMacroBody(Hotstring hs)
    {
        IReadOnlyList<MacroToken> tokens = MacroTokenParser.Parse(hs.Replacement).Tokens;

        List<string> lines = [];
        StringBuilder textAccumulator = new();
        int cursorIndex = -1;

        void FlushText()
        {
            if (textAccumulator.Length == 0) return;
            lines.Add($"SendText \"{EscapeStringLiteral(textAccumulator.ToString())}\"");
            textAccumulator.Clear();
        }

        int i = 0;
        while (i < tokens.Count)
        {
            switch (tokens[i])
            {
                case MacroToken.TextRun run:
                    textAccumulator.Append(run.Text);
                    i++;
                    break;

                case MacroToken.Cursor:
                    cursorIndex = i;
                    i++;
                    break;

                case MacroToken.Key key:
                    FlushText();
                    int count = 1;
                    while (i + 1 < tokens.Count && tokens[i + 1] is MacroToken.Key next && next.Name == key.Name)
                    {
                        count++;
                        i++;
                    }
                    lines.Add(count == 1 ? $"Send \"{{{key.Name}}}\"" : $"Send \"{{{key.Name} {count}}}\"");
                    i++;
                    break;
            }
        }
        FlushText();

        int leftCount = cursorIndex < 0
            ? 0
            : tokens.Skip(cursorIndex + 1).OfType<MacroToken.TextRun>().Sum(t => t.Text.Length);
        if (leftCount > 0)
            lines.Add($"Send \"{{Left {leftCount}}}\"");

        string body = string.Concat(lines.Select(line => $"\n\t{line}"));
        return $"\n{{{body}\n}}";
    }

    // Keep every hotstring on one physical line and its trigger free of characters
    // AHK v2 would otherwise reinterpret (backtick, a whitespace-preceded ';'). Backtick
    // must be escaped first so later escapes are not double-escaped.
    private static string Escape(string value) =>
        value
            .Replace("`", "``")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t")
            .Replace(";", "`;");

    // For AHK v2 double-quoted string contents inside a macro's SendText/Send lines.
    // Unlike Escape() above, no ';' handling is needed (there's no whitespace-preceded-';'
    // rule inside a quoted string literal). Backtick must be escaped first so later escapes
    // are not double-escaped.
    private static string EscapeStringLiteral(string value) =>
        value
            .Replace("`", "``")
            .Replace("\"", "`\"")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t");
}
