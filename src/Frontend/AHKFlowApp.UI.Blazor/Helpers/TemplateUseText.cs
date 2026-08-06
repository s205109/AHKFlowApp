namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>One Profile, and the keys each of its templates uses. Both lists hold canonical names.</summary>
internal sealed record ProfileTemplateUse(
    string ProfileName,
    IReadOnlyList<string> HeaderKeys,
    IReadOnlyList<string> FooterKeys);

/// <summary>
/// The notice shown when a Profile's header or footer template already uses a row's key.
/// </summary>
/// <remarks>
/// Synchronous and pure: it takes canonical key names and returns a string. Canonicalizing is the
/// caller's job, because <see cref="Services.IHotkeyKeyCatalog.CanonicalizeAsync"/> is asynchronous.
/// <para>
/// Matching reads the key alone. A wildcard hotkey fires whatever extra modifiers are held and
/// eclipses the plain hotkey, so a row carrying Ctrl is affected just as much as a bare one. See
/// https://www.autohotkey.com/docs/v2/Hotkeys.htm#wildcard.
/// </para>
/// <para>
/// The closing hedges on purpose. CONTEXT.md rules that a shortcut warning never promises what
/// happens when the keys are pressed.
/// </para>
/// </remarks>
internal static class TemplateUseText
{
    private const string Closing = "Your hotkey may not fire.";

    // Profile count is unbounded, so the sentence names a few and counts the rest.
    private const int MaxNamed = 3;

    private enum Matched { Header, Footer, Both }

    /// <summary>The notice, or null when no template uses the row's key.</summary>
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
        string verb = hits.Count == 1 && named[0].Where != Matched.Both ? "uses" : "use";

        return $"{Subject(named, overflow)} also {verb} {canonicalRowKey}. {Closing}";
    }

    private static bool Uses(IReadOnlyList<string> keys, string canonicalRowKey) =>
        keys.Any(k => string.Equals(k, canonicalRowKey, StringComparison.OrdinalIgnoreCase));

    // One grouped phrase when every Profile matched the same way, which is the common case. A
    // per-Profile phrase list otherwise, so a mixed result never names the wrong template.
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

    // Mirrors KnownShortcutWarning.JoinLabels, so both notices join names the same way.
    private static string JoinLabels(string[] labels) => labels.Length switch
    {
        0 => "Something",
        1 => labels[0],
        _ => $"{string.Join(", ", labels[..^1])} and {labels[^1]}",
    };
}
