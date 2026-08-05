namespace HeaderKeyUsePrototype;

/// <summary>
/// PROTOTYPE — the keeper half. Pure, no I/O, no terminal code.
///
/// Question this answers: given real Profile template text, does the agreed parser rule pick out
/// exactly the keys a template uses as hotkeys, and no others?
///
/// The agreed rule (grilling Q8, option A):
///   - Skip a line whose first non-space character is ';'
///   - Read only modifier-free lines. A line carrying '^' '!' '+' '#' '&lt;' '&gt;' before the key is an
///     ordinary hand-written hotkey and is skipped
///   - Skip custom combinations, which contain '&amp;' on the left of '::'
///   - Accept optional '*' '~' '$' prefixes, then a key name, then optional " up", then "::"
///   - "Key up::" and "Key::" both use the same one key
///
/// Runs over a header template and a footer template alike — both reach the generated script.
/// </summary>
public static class TemplateKeyUses
{
    private const string Prefixes = "*~$";
    private const string ModifierSymbols = "^!+#<>";

    /// <summary>Every key the template uses as a hotkey. Case-insensitive, de-duplicated.</summary>
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

    /// <summary>The key one line uses, or null when the line uses none.</summary>
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
