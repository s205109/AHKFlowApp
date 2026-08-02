using AHKFlowApp.UI.Blazor.DTOs;
using AHKFlowApp.UI.Blazor.Services;
using AHKFlowApp.UI.Blazor.Validation;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// Known-shortcut notices for a page of hotkey rows, keyed by the combination label the row
/// renders. A combination that matches nothing is absent, so a <c>TryGetValue</c> miss is the
/// "no marker" answer.
/// </summary>
/// <remarks>
/// Two key forms are in play and they must not be swapped. The display label is built from the
/// raw key, and it is both the dictionary key and the label the notice names. The canonical key
/// goes to <see cref="KnownShortcutWarning.Match"/> and nowhere else. A row keyed "Esc" with Ctrl
/// held displays "Ctrl+Esc" and canonicalizes to "Escape". Store the notice under "Ctrl+Escape"
/// and the cell — which looks up "Ctrl+Esc", the string it is about to print — misses every time.
/// </remarks>
internal static class KnownShortcutNotices
{
    public static async Task<IReadOnlyDictionary<string, string>> BuildAsync(
        IEnumerable<HotkeyEditModel> items,
        IHotkeyKeyCatalog keys,
        IKnownShortcutCatalog knownShortcuts,
        ILogger logger,
        CancellationToken ct)
    {
        Dictionary<string, string> notices = [];

        // One row per distinct label. Twenty rows sharing five combinations cost five
        // canonicalize calls, not twenty.
        List<HotkeyEditModel> distinct =
        [
            .. items
                .GroupBy(item => HotkeyActionDisplay.ComboLabel(item), StringComparer.Ordinal)
                .Select(group => group.First())
        ];

        if (distinct.Count == 0)
            return notices;

        try
        {
            // Session-cached: only the first read in a session reaches the network.
            KnownShortcutCatalogDto? catalog = await knownShortcuts.GetAsync(ct);

            if (catalog is null)
            {
                // The fetch failed. No marker anywhere, and a trace in the browser console. The
                // cache does not remember the failure, so the next load tries again. This is the
                // rule the edit dialog already follows.
                logger.LogWarning("Known-shortcut list could not be read; showing no markers.");
                return notices;
            }

            foreach (HotkeyEditModel item in distinct)
            {
                string label = HotkeyActionDisplay.ComboLabel(item);

                // A key registry that has not loaded hands the key back unchanged, so an alias
                // such as "Esc" misses the "Escape" row. The marker is advice, so a miss is the
                // safe outcome.
                string canonical = await keys.CanonicalizeAsync(item.Key, ct);

                KnownShortcutDto? match = KnownShortcutWarning.Match(
                    catalog, canonical, item.Ctrl, item.Alt, item.Shift, item.Win);

                if (match is not null)
                    notices[label] = KnownShortcutWarning.TextFor(match, label);
            }
        }
        catch (OperationCanceledException)
        {
            // The page moved on. Whatever was resolved so far is handed back; a newer load
            // replaces it.
        }
        catch (Exception ex)
        {
            // Caught broadly on purpose, the same way the edit dialog does. The marker is
            // advisory, and a list page must never fail to render because a notice could not be
            // worked out.
            logger.LogWarning(ex, "Known-shortcut markers could not be built.");
        }

        return notices;
    }
}
