namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// The keys a Profile's header or footer template uses as hotkeys.
/// </summary>
/// <remarks>
/// Only modifier-free lines are read. A template line carrying its own modifiers, such as
/// <c>^!c::</c>, is an ordinary hand-written hotkey: it collides with one exact combination, not
/// with every row on that key, so reading it would make every row with key C warn.
/// <para>
/// The keys come back spelled as the template spells them. Canonicalizing is the caller's job,
/// because <see cref="Services.IHotkeyKeyCatalog.CanonicalizeAsync"/> is asynchronous and this
/// stays a pure function.
/// </para>
/// </remarks>
internal static class TemplateKeyUses
{
    private const string Prefixes = "*~$";
    private const string ModifierSymbols = "^!+#<>";

    /// <summary>Every key the template uses as a hotkey. De-duplicated, ignoring case.</summary>
    public static IReadOnlyList<string> Parse(string template)
    {
        List<string> keys = [];
        HashSet<string> seen = new(StringComparer.OrdinalIgnoreCase);

        foreach (string rawLine in template.Split('\n'))
        {
            string? key = KeyUsedBy(rawLine);

            if (key is not null && seen.Add(key))
                keys.Add(key);
        }

        return keys;
    }

    // The key one line uses, or null when the line uses none.
    private static string? KeyUsedBy(string rawLine)
    {
        string line = rawLine.Trim();

        if (line.Length == 0 || line[0] == ';')
            return null;

        int doubleColon = line.IndexOf("::", StringComparison.Ordinal);

        if (doubleColon < 0)
            return null;

        string left = line[..doubleColon];

        // A custom combination such as "LCtrl & RAlt::" is not modifier-free.
        if (left.Contains('&'))
            return null;

        int i = 0;

        while (i < left.Length && Prefixes.Contains(left[i]))
            i++;

        if (i >= left.Length || ModifierSymbols.Contains(left[i]))
            return null;

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

        return key;
    }
}
