namespace HeaderKeyUsePrototype;

/// <summary>
/// One Profile, and the keys each of its templates uses. Both lists hold canonical key names —
/// the caller canonicalizes before building this, because canonicalizing is asynchronous
/// (<c>IHotkeyKeyCatalog.CanonicalizeAsync</c> returns <c>ValueTask&lt;string&gt;</c>) and this
/// composer stays pure and synchronous.
/// </summary>
public sealed record ProfileTemplateUse(
    string ProfileName,
    IReadOnlyList<string> HeaderKeys,
    IReadOnlyList<string> FooterKeys);

/// <summary>
/// PROTOTYPE — the keeper half. Pure, no I/O, no async.
///
/// Writes the notice agreed in grilling Q7, option A, extended to name which template matched:
///   "The header template in Work also uses CapsLock. Your hotkey may not fire."
///   "The header and footer templates in Work also use CapsLock. Your hotkey may not fire."
///   "The header templates in Work and Games also use CapsLock. Your hotkey may not fire."
///
/// Matching is on the key alone (grilling Q6). The row's modifiers are not consulted, because a
/// wildcard hotkey fires whatever extra modifiers are held and eclipses the plain hotkey.
/// See https://www.autohotkey.com/docs/v2/Hotkeys.htm#wildcard.
/// </summary>
public static class TemplateUseText
{
    private const string Closing = "Your hotkey may not fire.";

    /// <summary>Profile count is unbounded, so the sentence names at most this many.</summary>
    private const int MaxNamed = 3;

    private enum Matched { Header, Footer, Both }

    /// <summary>
    /// The notice, or null when no template uses the row's key.
    /// </summary>
    /// <param name="uses">Only the Profiles the row belongs to. Keys already canonical.</param>
    /// <param name="canonicalRowKey">The row's key, already canonical.</param>
    public static string? TextFor(IReadOnlyList<ProfileTemplateUse> uses, string canonicalRowKey)
    {
        if (string.IsNullOrWhiteSpace(canonicalRowKey))
            return null;

        List<(string Profile, Matched Where)> hits = [];

        foreach (ProfileTemplateUse use in uses)
        {
            bool header = Uses(use.HeaderKeys, canonicalRowKey);
            bool footer = Uses(use.FooterKeys, canonicalRowKey);

            if (header && footer)
                hits.Add((use.ProfileName, Matched.Both));
            else if (header)
                hits.Add((use.ProfileName, Matched.Header));
            else if (footer)
                hits.Add((use.ProfileName, Matched.Footer));
        }

        if (hits.Count == 0)
            return null;

        int overflow = Math.Max(0, hits.Count - MaxNamed);
        List<(string Profile, Matched Where)> named = [.. hits.Take(MaxNamed)];

        // "uses" only when one Profile matched through one template. Everything else is plural,
        // including a single Profile whose header and footer both match.
        bool singular = hits.Count == 1 && named[0].Where != Matched.Both;
        string verb = singular ? "uses" : "use";

        return $"{Subject(named, overflow)} also {verb} {canonicalRowKey}. {Closing}";
    }

    private static bool Uses(IReadOnlyList<string> keys, string canonicalRowKey) =>
        keys.Any(k => string.Equals(k, canonicalRowKey, StringComparison.OrdinalIgnoreCase));

    // One grouped phrase when every Profile matched the same way, which is the common case. A
    // per-Profile phrase list otherwise, so a mixed result never claims the wrong template.
    private static string Subject(List<(string Profile, Matched Where)> named, int overflow)
    {
        string tail = overflow > 0 ? $" and {overflow} more" : "";

        if (named.Select(h => h.Where).Distinct().Count() == 1)
        {
            string label = Label(named[0].Where, plural: named.Count > 1 || named[0].Where == Matched.Both);
            return $"The {label} in {JoinLabels([.. named.Select(h => h.Profile)])}{tail}";
        }

        string[] phrases =
        [
            .. named.Select(h => $"the {Label(h.Where, plural: h.Where == Matched.Both)} in {h.Profile}")
        ];

        string joined = JoinLabels(phrases) + tail;

        return char.ToUpperInvariant(joined[0]) + joined[1..];
    }

    private static string Label(Matched where, bool plural) => where switch
    {
        Matched.Both => "header and footer templates",
        Matched.Footer => plural ? "footer templates" : "footer template",
        _ => plural ? "header templates" : "header template",
    };

    // Mirrors KnownShortcutWarning.JoinLabels (KnownShortcutWarning.cs:182).
    private static string JoinLabels(string[] labels) => labels.Length switch
    {
        0 => "Something",
        1 => labels[0],
        _ => $"{string.Join(", ", labels[..^1])} and {labels[^1]}",
    };
}
