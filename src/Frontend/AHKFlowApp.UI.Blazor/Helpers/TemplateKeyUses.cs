namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// One hotkey a Profile's header or footer template defines: the key it uses, whether it is a
/// wildcard hotkey, and the modifiers it declares.
/// </summary>
/// <remarks>
/// A side-specific modifier such as <c>&lt;^</c> is read as its plain modifier. A Hotkey row cannot
/// say "left Ctrl only", so the side is dropped and the two are treated as the same modifier.
/// </remarks>
internal sealed record TemplateHotkey(
    string Key,
    bool Wildcard,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win);

/// <summary>
/// The hotkeys a Profile's header or footer template defines.
/// </summary>
/// <remarks>
/// The keys come back spelled as the template spells them. Canonicalizing is the caller's job,
/// because <see cref="Services.IHotkeyKeyCatalog.CanonicalizeAsync"/> is asynchronous and this
/// stays a pure function.
/// </remarks>
internal static class TemplateKeyUses
{
    private const string Prefixes = "*~$";

    /// <summary>Every hotkey the template defines. De-duplicated, ignoring the key's case.</summary>
    public static IReadOnlyList<TemplateHotkey> Parse(string template)
    {
        List<TemplateHotkey> hotkeys = [];
        HashSet<TemplateHotkey> seen = [];

        foreach (string rawLine in template.Split('\n'))
        {
            TemplateHotkey? hotkey = HotkeyOn(rawLine);

            if (hotkey is not null && seen.Add(hotkey with { Key = hotkey.Key.ToUpperInvariant() }))
                hotkeys.Add(hotkey);
        }

        return hotkeys;
    }

    // The hotkey one line defines, or null when the line defines none.
    private static TemplateHotkey? HotkeyOn(string rawLine)
    {
        string line = rawLine.Trim();

        if (line.Length == 0 || line[0] == ';')
            return null;

        int doubleColon = line.IndexOf("::", StringComparison.Ordinal);

        if (doubleColon < 0)
            return null;

        string left = line[..doubleColon];

        // A custom combination such as "LCtrl & RAlt::" names two keys, so it is left alone.
        if (left.Contains('&'))
            return null;

        int i = 0;
        bool wildcard = false;

        while (i < left.Length && Prefixes.Contains(left[i]))
        {
            wildcard |= left[i] == '*';
            i++;
        }

        bool ctrl = false;
        bool alt = false;
        bool shift = false;
        bool win = false;

        // "<" and ">" pick a side for the modifier that follows. A row has no side, so they are
        // skipped and the modifier itself is what counts.
        while (i < left.Length)
        {
            switch (left[i])
            {
                case '<' or '>':
                    break;
                case '^':
                    ctrl = true;
                    break;
                case '!':
                    alt = true;
                    break;
                case '+':
                    shift = true;
                    break;
                case '#':
                    win = true;
                    break;
                default:
                    goto done;
            }

            i++;
        }

    done:
        int keyStart = i;

        while (i < left.Length && (char.IsLetterOrDigit(left[i]) || left[i] == '_'))
            i++;

        if (i == keyStart)
            return null;

        string key = left[keyStart..i];
        string rest = left[i..].Trim();

        // A key-up hotkey uses the same key as its key-down half.
        if (rest.Length != 0 && !rest.Equals("up", StringComparison.OrdinalIgnoreCase))
            return null;

        return new TemplateHotkey(key, wildcard, ctrl, alt, shift, win);
    }
}
