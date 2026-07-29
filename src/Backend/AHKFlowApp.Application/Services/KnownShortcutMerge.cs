using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Folds the curated manifest, an owner's own records, and their ignores into one list.
/// </summary>
/// <remarks>
/// Aggregates, never replaces. An owner record adds a use to a combination; it cannot remove or
/// weaken a built-in fact. The dialog and the management page need different answers — the
/// dialog must not warn about an ignored use, the page must show it so it can be brought back —
/// so this class offers one method each rather than one method with a flag.
/// </remarks>
internal static class KnownShortcutMerge
{
    // Grouping key only, never shown. MatchKey is uppercased so "e" and "E" collapse into one row.
    // The spelling the page displays travels separately, in the DTO's own Key.
    private readonly record struct Combo(string MatchKey, bool Ctrl, bool Alt, bool Shift, bool Win);

    /// <summary>Active uses only. Combinations left with no visible use are dropped.</summary>
    public static IReadOnlyList<KnownShortcutDto> ForDialog(
        IReadOnlyList<CustomKnownShortcut> owned,
        IReadOnlyList<IgnoredKnownShortcut> ignored) =>
        ForDialog(KnownShortcutCatalog.All, owned, ignored);

    /// <inheritdoc cref="ForDialog(IReadOnlyList{CustomKnownShortcut}, IReadOnlyList{IgnoredKnownShortcut})"/>
    /// <param name="builtIns">
    /// The built-in rows to merge against. Production always passes <see cref="KnownShortcutCatalog.All"/>
    /// through the two-argument overload; tests pass a hand-built list so they can exercise a row
    /// shape the shipped manifest does not contain yet, such as a non-null <c>WarningText</c>.
    /// </param>
    /// <param name="owned">The owner's own records.</param>
    /// <param name="ignored">The built-in uses the owner has silenced.</param>
    internal static IReadOnlyList<KnownShortcutDto> ForDialog(
        IReadOnlyList<KnownShortcut> builtIns,
        IReadOnlyList<CustomKnownShortcut> owned,
        IReadOnlyList<IgnoredKnownShortcut> ignored) =>
    [
        .. ForManagement(builtIns, owned, ignored)
            .Select(s => new KnownShortcutDto(
                s.Id, s.Key, s.Ctrl, s.Alt, s.Shift, s.Win,
                [
                    .. s.Uses.Where(u => !u.IsIgnored)
                        .Select(u => new ShortcutUseDto(u.UsedBy, u.Protection, u.Scope, u.Does))
                ],
                // Carried through, never dropped. The frontend returns this verbatim when it is
                // set, so hardcoding null here would silently discard a catalog override.
                s.WarningText))
            .Where(s => s.Uses.Count > 0)
    ];

    /// <summary>Every use, ignored ones included, each carrying the state the page can change.</summary>
    public static IReadOnlyList<ManagedKnownShortcutDto> ForManagement(
        IReadOnlyList<CustomKnownShortcut> owned,
        IReadOnlyList<IgnoredKnownShortcut> ignored) =>
        ForManagement(KnownShortcutCatalog.All, owned, ignored);

    /// <inheritdoc cref="ForManagement(IReadOnlyList{CustomKnownShortcut}, IReadOnlyList{IgnoredKnownShortcut})"/>
    /// <param name="builtIns">See the matching parameter on <see cref="ForDialog(IReadOnlyList{KnownShortcut}, IReadOnlyList{CustomKnownShortcut}, IReadOnlyList{IgnoredKnownShortcut})"/>.</param>
    /// <param name="owned">The owner's own records.</param>
    /// <param name="ignored">The built-in uses the owner has silenced.</param>
    internal static IReadOnlyList<ManagedKnownShortcutDto> ForManagement(
        IReadOnlyList<KnownShortcut> builtIns,
        IReadOnlyList<CustomKnownShortcut> owned,
        IReadOnlyList<IgnoredKnownShortcut> ignored)
    {
        // (shortcut id, used-by) is the ignore key: ignoring is per use, not per combination.
        HashSet<(string, string)> silenced =
            [.. ignored.Select(i => (i.ShortcutId, i.UsedBy))];

        Dictionary<Combo, ManagedKnownShortcutDto> byCombo = [];

        foreach (KnownShortcut builtIn in builtIns)
        {
            string key = Canonical(builtIn.Key);
            byCombo[ComboOf(key, builtIn.Ctrl, builtIn.Alt, builtIn.Shift, builtIn.Win)] =
                new ManagedKnownShortcutDto(
                    builtIn.Id, key, builtIn.Ctrl, builtIn.Alt, builtIn.Shift, builtIn.Win,
                    [
                        .. builtIn.Uses.Select(u => new ManagedShortcutUseDto(
                            u.UsedBy, u.Protection, u.Scope, u.Does,
                            ShortcutRecordOrigin.BuiltIn,
                            OwnerRecordId: null,
                            IsIgnored: silenced.Contains((builtIn.Id, u.UsedBy))))
                    ],
                    builtIn.WarningText);
        }

        foreach (CustomKnownShortcut record in owned)
        {
            string key = Canonical(record.Key);
            Combo combo = ComboOf(key, record.Ctrl, record.Alt, record.Shift, record.Win);

            ManagedShortcutUseDto use = new(
                record.UsedBy, record.Protection, record.Scope, record.Does,
                ShortcutRecordOrigin.Owner,
                OwnerRecordId: record.Id,
                IsIgnored: false);

            if (byCombo.TryGetValue(combo, out ManagedKnownShortcutDto? existing))
            {
                // Adds a use to the built-in row. Its Key and WarningText both stay as they were —
                // an owner record never overwrites a built-in fact.
                byCombo[combo] = existing with { Uses = [.. existing.Uses, use] };
            }
            else
            {
                // Owner-only combination. The id is synthetic and never sent back to the server.
                // No built-in row exists, so there is no WarningText to carry.
                byCombo[combo] = new ManagedKnownShortcutDto(
                    $"owner.{record.Id}", key, record.Ctrl, record.Alt, record.Shift, record.Win,
                    [use],
                    WarningText: null);
            }
        }

        return [.. byCombo.Values];
    }

    // Canonicalize before every comparison, or "Esc" and "Escape" produce two rows for one key.
    // TryCanonicalize writes an empty string when it fails, so keep the caller's spelling instead:
    // an unrecognised key must still show as itself, never as a blank cell.
    private static string Canonical(string key) =>
        HotkeyKeys.TryCanonicalize(key, out string canonical) ? canonical : key;

    // Uppercase only inside the grouping key. The canonical spelling passed in is untouched.
    private static Combo ComboOf(string canonicalKey, bool ctrl, bool alt, bool shift, bool win) =>
        new(canonicalKey.ToUpperInvariant(), ctrl, alt, shift, win);
}
