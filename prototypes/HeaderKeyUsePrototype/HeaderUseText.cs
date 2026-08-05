namespace HeaderKeyUsePrototype;

/// <summary>One Profile, and the keys its header template uses.</summary>
public sealed record ProfileHeaderUse(string ProfileName, IReadOnlyList<string> Keys);

/// <summary>
/// PROTOTYPE — the keeper half. Pure, no I/O.
///
/// Writes the notice agreed in grilling Q7, option A:
///   "The header template in Work also uses CapsLock. Your hotkey may not fire."
///
/// Matching is on the key alone (grilling Q6). The row's modifiers are not consulted, because a
/// wildcard hotkey fires whatever extra modifiers are held (AHK v2 docs, Hotkeys.htm:99) and
/// eclipses the plain hotkey (Hotkeys.htm:102).
/// </summary>
public static class HeaderUseText
{
    private const string Closing = "Your hotkey may not fire.";

    /// <summary>
    /// The notice, or null when no header uses the row's key.
    /// </summary>
    /// <param name="uses">Only the Profiles the row belongs to.</param>
    /// <param name="rowKey">The row's key. Already canonical in the real app.</param>
    /// <param name="canonicalize">
    /// Stands in for <c>IHotkeyKeyCatalog.CanonicalizeAsync</c>. Returns null for a name the key
    /// registry does not know.
    /// </param>
    public static string? TextFor(
        IReadOnlyList<ProfileHeaderUse> uses,
        string rowKey,
        Func<string, string?> canonicalize)
    {
        string? canonicalRowKey = canonicalize(rowKey);

        if (string.IsNullOrWhiteSpace(canonicalRowKey))
            return null;

        string[] matching =
        [
            .. uses
                .Where(u => u.Keys.Any(k =>
                    string.Equals(canonicalize(k), canonicalRowKey, StringComparison.OrdinalIgnoreCase)))
                .Select(u => u.ProfileName)
        ];

        if (matching.Length == 0)
            return null;

        string subject = matching.Length == 1
            ? $"The header template in {matching[0]}"
            : $"The header templates in {JoinLabels(matching)}";

        string verb = matching.Length == 1 ? "uses" : "use";

        return $"{subject} also {verb} {canonicalRowKey}. {Closing}";
    }

    // Mirrors KnownShortcutWarning.JoinLabels (KnownShortcutWarning.cs:182).
    private static string JoinLabels(string[] labels) => labels.Length switch
    {
        0 => "Something",
        1 => labels[0],
        _ => $"{string.Join(", ", labels[..^1])} and {labels[^1]}",
    };
}
