namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>One Profile, and the hotkeys each of its templates defines. Keys are already canonical.</summary>
internal sealed record ProfileTemplateUse(
    string ProfileName,
    IReadOnlyList<TemplateHotkey> HeaderHotkeys,
    IReadOnlyList<TemplateHotkey> FooterHotkeys);

/// <summary>The row being edited: its canonical key, its modifiers, and the label to show.</summary>
internal sealed record RowCombination(
    string CanonicalKey,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string Label);

/// <summary>
/// The notice shown when a Profile's header or footer template already uses a row's keys.
/// </summary>
/// <remarks>
/// Synchronous and pure: it takes canonical key names and returns a string. Canonicalizing is the
/// caller's job, because <see cref="Services.IHotkeyKeyCatalog.CanonicalizeAsync"/> is asynchronous.
/// <para>
/// Matching follows AutoHotkey. A plain template hotkey fires only for the modifiers it declares,
/// so it matches a row that carries exactly those. A wildcard hotkey fires whatever extra
/// modifiers are held, so it matches any row that carries at least its own. See
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

    /// <summary>The notice, or null when no template uses the row's keys.</summary>
    /// <param name="uses">Only the Profiles the row belongs to. Keys already canonical.</param>
    /// <param name="row">The row's keys, already canonical.</param>
    public static string? TextFor(IReadOnlyList<ProfileTemplateUse> uses, RowCombination row)
    {
        if (string.IsNullOrWhiteSpace(row.CanonicalKey))
            return null;

        List<(string Profile, Matched Where)> hits = [];

        foreach (ProfileTemplateUse use in uses)
        {
            bool header = Uses(use.HeaderHotkeys, row);
            bool footer = Uses(use.FooterHotkeys, row);

            if (header && footer)
                hits.Add((use.ProfileName, Matched.Both));
            else if (header)
                hits.Add((use.ProfileName, Matched.Header));
            else if (footer)
                hits.Add((use.ProfileName, Matched.Footer));
        }

        if (hits.Count == 0)
            return null;

        // "uses" only when one Profile matched through one template. Everything else is plural,
        // including a single Profile whose header and footer both match.
        string verb = hits.Count == 1 && hits[0].Where != Matched.Both ? "uses" : "use";

        return $"{Subject(hits)} also {verb} {row.Label}. {Closing}";
    }

    private static bool Uses(IReadOnlyList<TemplateHotkey> hotkeys, RowCombination row) =>
        hotkeys.Any(h => Matches(h, row));

    // A wildcard hotkey fires while extra modifiers are held, so the row only has to carry the
    // modifiers the template declares. Every other hotkey needs the same modifiers exactly.
    private static bool Matches(TemplateHotkey hotkey, RowCombination row)
    {
        if (!string.Equals(hotkey.Key, row.CanonicalKey, StringComparison.OrdinalIgnoreCase))
            return false;

        return hotkey.Wildcard
            ? (!hotkey.Ctrl || row.Ctrl)
                && (!hotkey.Alt || row.Alt)
                && (!hotkey.Shift || row.Shift)
                && (!hotkey.Win || row.Win)
            : hotkey.Ctrl == row.Ctrl
                && hotkey.Alt == row.Alt
                && hotkey.Shift == row.Shift
                && hotkey.Win == row.Win;
    }

    // One grouped phrase when every Profile matched the same way, which is the common case. A
    // per-Profile phrase list otherwise, so a mixed result never names the wrong template.
    // Grouping reads every hit, not only the named ones: an unnamed footer hit folded under a
    // header subject would say the wrong thing about the Profiles it stands for.
    private static string Subject(List<(string Profile, Matched Where)> hits)
    {
        int overflow = Math.Max(0, hits.Count - MaxNamed);
        List<(string Profile, Matched Where)> named = [.. hits.Take(MaxNamed)];
        string tail = overflow > 0 ? $" and {overflow} more" : "";

        if (hits.Select(h => h.Where).Distinct().Count() == 1)
        {
            string label = Label(hits[0].Where, plural: hits.Count > 1 || hits[0].Where == Matched.Both);
            return $"The {label} in {JoinLabels([.. named.Select(h => h.Profile)])}{tail}";
        }

        // The count joins the phrase list rather than trailing it. Trailing it would read as part
        // of the last phrase, which names one template kind the counted Profiles may not share.
        string[] phrases =
        [
            .. named.Select(h => $"the {Label(h.Where, plural: h.Where == Matched.Both)} in {h.Profile}"),
            .. overflow > 0 ? new[] { $"{overflow} more" } : [],
        ];

        string joined = JoinLabels(phrases);

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
