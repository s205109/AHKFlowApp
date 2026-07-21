using System.Text;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotstring lines. Deterministic option order: X * ? C O T.
/// Clipboard delivery emits X * ? C, while typed Text retains * ? C O T.
/// </summary>
internal static class HotstringEmitter
{
    // Bare "#HotIf" (no expression) clears any preceding #HotIf's context, restoring
    // global scope for everything emitted after it. Single source shared with the
    // preview handler so both code paths use the identical close string.
    public const string HotIfClose = "#HotIf";
    public const string PasteHelperName = "AhkFlow_PasteReplacement";
    public const string PasteHelperFunction =
        """
        AhkFlow_PasteReplacement(text, endChar := "") {
            saved := ClipboardAll()
            A_Clipboard := text
            if !ClipWait(1) {
                A_Clipboard := saved
                return
            }
            Send "^v"
            Sleep 150
            A_Clipboard := saved
            saved := ""
            if (endChar != "")
                SendText endChar
        }
        """;

    // Raw is emitted verbatim: its Replacement already holds the entire ":opts:trigger::"
    // definition (plus any brace body), so the ":{options}:{trigger}::{body}" template is
    // bypassed entirely — re-prefixing would double the definition. AhkScriptGenerator adds
    // each Emit result to a line list joined with "\n", so a multi-line definition slots in
    // as multiple physical lines.
    public static string Emit(Hotstring hs)
    {
        if (hs.Kind == HotstringKind.Raw)
            return hs.Replacement;

        return ResolveEffectiveDelivery(hs) == HotstringDelivery.ClipboardPaste
            ? $":{BuildClipboardOptions(hs)}:{Escape(hs.Trigger)}::{BuildClipboardBody(hs)}"
            : $":{BuildOptions(hs)}:{Escape(hs.Trigger)}::{BuildBody(hs)}";
    }

    public static HotstringDelivery ResolveEffectiveDelivery(Hotstring hs) =>
        hs.Kind == HotstringKind.Text
            && (hs.Delivery == HotstringDelivery.ClipboardPaste
                || (hs.Delivery == HotstringDelivery.Auto
                    && hs.Replacement.Length >= HotstringDeliveryDefaults.AutoClipboardThresholdChars))
            ? HotstringDelivery.ClipboardPaste
            : HotstringDelivery.Type;

    // Single source of truth for Description-as-comment emission, shared by AhkScriptGenerator
    // (script lines above each entity) and the preview handler (snippet). Each Description line
    // becomes a "; " comment line; an empty/whitespace Description yields nothing.
    public static IEnumerable<string> DescriptionCommentLines(string? description)
    {
        if (string.IsNullOrWhiteSpace(description))
            yield break;

        foreach (string line in description.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
            yield return line.Length == 0 ? ";" : $"; {line}";
    }

    // ContextValue has already passed validation guaranteeing no double-quote, backtick, or
    // control characters (see HotstringRules.AddWindowContextRules) — safe to embed raw here.
    public static string EmitHotIfOpen(WindowMatchType matchType, string value)
    {
        string criterion = matchType switch
        {
            WindowMatchType.Executable => $"ahk_exe {value}",
            WindowMatchType.WindowClass => $"ahk_class {value}",
            WindowMatchType.TitleContains => value,
            _ => throw new InvalidOperationException($"Unsupported WindowMatchType: {matchType}"),
        };
        return $"#HotIf WinActive(\"{criterion}\")";
    }

    private static string BuildOptions(Hotstring hs)
    {
        bool isDateTime = hs.Kind == HotstringKind.DateTime;
        string options = (isDateTime ? "X" : "") + BuildTriggerOptions(hs);
        if (hs.OmitEndingCharacter && hs.IsEndingCharacterRequired) options += "O"; // O is meaningless with *
        if (hs.Kind == HotstringKind.Text) options += "T"; // Text always emits literally (WYSIWYG) — D1. Brace-body kinds (DateTime/Macro/Raw) have no auto-replace text and must never emit T.
        return options;
    }

    private static string BuildClipboardOptions(Hotstring hs) =>
        $"X{BuildTriggerOptions(hs)}";

    private static string BuildTriggerOptions(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        if (hs.IsCaseSensitive) options += "C";
        return options;
    }

    private static string BuildClipboardBody(Hotstring hs)
    {
        string endCharArgument = hs.IsEndingCharacterRequired && !hs.OmitEndingCharacter
            ? ", A_EndChar"
            : "";
        return $"{PasteHelperName}(\"{AhkEscaping.EscapeStringLiteral(hs.Replacement)}\"{endCharArgument})";
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
            lines.Add($"SendText \"{AhkEscaping.EscapeStringLiteral(textAccumulator.ToString())}\"");
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

}
