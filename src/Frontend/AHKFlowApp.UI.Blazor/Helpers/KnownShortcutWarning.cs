using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// Finds the known shortcut a combination matches, and writes the notice shown for it.
/// </summary>
/// <remarks>
/// Text is composed from the uses, never switched on one value. There is no two-way answer to
/// "what happens when the user presses this": AutoHotkey may register the hotkey or install its
/// own hook, and a low-level keyboard hook installed earlier can swallow the keystroke. So the
/// notice says what else uses the keys, and stops short of promising a result.
/// </remarks>
internal static class KnownShortcutWarning
{
    // States what Windows does, rather than predicting what the hotkey will do. Says nothing
    // about what other apps can or cannot see — no Microsoft source backs that, and PowerToys
    // remaps keys at the low level. Avoids "reserves": CONTEXT.md rules that word out.
    private const string ProtectedClosing =
        "Windows handles these keys itself.";

    // One short clause. This closing appears on almost every warning, so length is the cost.
    // "may" hedges on purpose — the warning never promises an outcome.
    private const string NormalClosing =
        "Your hotkey may override this shortcut.";

    // Only owner records carry Unknown, and those are Stage 2, so nothing shipped reaches this
    // yet. Kept because the enum member is persisted in Stage 2 and the composer must not need
    // reworking to accept it.
    private const string UnknownClosing =
        "What happens when you press these keys depends on what else is installed.";

    private const string ForegroundTail = ", but only while that application is in front.";

    /// <summary>
    /// The known shortcut this combination matches, or null. The key must already be canonical —
    /// call <c>IHotkeyKeyCatalog.CanonicalizeAsync</c> first, or "Esc" misses the "Escape" row.
    /// </summary>
    public static KnownShortcutDto? Match(
        KnownShortcutCatalogDto? catalog,
        string? canonicalKey,
        bool ctrl,
        bool alt,
        bool shift,
        bool win)
    {
        if (catalog is null || string.IsNullOrWhiteSpace(canonicalKey))
            return null;

        return catalog.Shortcuts.FirstOrDefault(s =>
            s.Ctrl == ctrl && s.Alt == alt && s.Shift == shift && s.Win == win
            && string.Equals(s.Key, canonicalKey, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>The notice for a matched shortcut. Plain text — MudAlert renders it verbatim.</summary>
    public static string TextFor(KnownShortcutDto shortcut, string comboLabel)
    {
        if (shortcut.WarningText is { Length: > 0 } overrideText)
            return overrideText;

        List<string> sentences = [];

        // Group by what the keys do, so two products doing the same thing share one sentence.
        foreach (IGrouping<(string Does, ShortcutScope Scope), ShortcutUseDto> group in
                 shortcut.Uses.GroupBy(u => (u.Does, u.Scope)))
        {
            string[] labels = [.. group.Select(u => u.UsedBy)];
            string subject = JoinLabels(labels);
            string verb = labels.Length == 1 ? "uses" : "use";
            string tail = group.Key.Scope == ShortcutScope.Foreground ? ForegroundTail : ".";

            sentences.Add($"{subject} {verb} {comboLabel} to {group.Key.Does}{tail}");
        }

        sentences.Add(Closing(shortcut));

        return string.Join(" ", sentences);
    }

    private static string Closing(KnownShortcutDto shortcut)
    {
        if (shortcut.Uses.Any(u => u.Protection == ShortcutProtection.Protected))
            return ProtectedClosing;

        return shortcut.Uses.Any(u => u.Protection == ShortcutProtection.Normal)
            ? NormalClosing
            : UnknownClosing;
    }

    private static string JoinLabels(string[] labels) => labels.Length switch
    {
        0 => "Something",
        1 => labels[0],
        _ => $"{string.Join(", ", labels[..^1])} and {labels[^1]}",
    };
}
