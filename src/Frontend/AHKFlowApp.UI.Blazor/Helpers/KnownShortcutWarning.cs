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

    // Modifier destinations, mapped to the name the notice uses for them. A left or right variant
    // reads as the plain modifier, because remapping to RCtrl reaches every Ctrl shortcut just the
    // same. "the Windows key" is spelled out: "Shortcuts that use Win may also respond" is hard to
    // read, while Ctrl, Alt and Shift are already the words the combination label uses.
    private static readonly Dictionary<string, string> s_modifierLabels = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Ctrl"] = "Ctrl",
        ["LCtrl"] = "Ctrl",
        ["RCtrl"] = "Ctrl",
        ["Alt"] = "Alt",
        ["LAlt"] = "Alt",
        ["RAlt"] = "Alt",
        ["Shift"] = "Shift",
        ["LShift"] = "Shift",
        ["RShift"] = "Shift",
        ["LWin"] = "the Windows key",
        ["RWin"] = "the Windows key",
    };

    // Agrees with the subject. One sentence can name several products — "Chrome and Edge use
    // Ctrl+T …" — and a fixed singular tail made that sentence disagree with itself.
    private const string ForegroundTailOne = ", but only while that application is in front.";

    private const string ForegroundTailMany = ", but only while those applications are in front.";

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

        List<string> sentences = UseSentences(shortcut, comboLabel);

        sentences.Add(Closing(shortcut));

        return string.Join(" ", sentences);
    }

    /// <summary>
    /// The notice for a remap destination, or null when the destination says nothing. The key must
    /// already be canonical — call <c>IHotkeyKeyCatalog.CanonicalizeAsync</c> first.
    /// </summary>
    /// <remarks>
    /// The destination is looked up with no modifiers. AutoHotkey releases modifiers that are on
    /// the source and not on the destination, so <c>^F1::Volume_Mute</c> sends a bare
    /// <c>Volume_Mute</c>. Modifiers a person holds on top of the source do carry through, but
    /// AHKFlow cannot know those, so the notice does not describe them.
    /// <para>
    /// This never reuses <see cref="TextFor"/>. That closing is about overriding a shortcut, and a
    /// remap destination does the opposite — it adds another way to send the destination key. The
    /// wording stops at "may also respond": a remapped key cannot reach a hook hotkey by default,
    /// so anything firmer would be a promise AutoHotkey does not keep.
    /// </para>
    /// </remarks>
    public static string? DestinationTextFor(
        KnownShortcutCatalogDto? catalog,
        string? canonicalDestination,
        string sourceComboLabel)
    {
        if (string.IsNullOrWhiteSpace(canonicalDestination))
            return null;

        KnownShortcutDto? match =
            Match(catalog, canonicalDestination, ctrl: false, alt: false, shift: false, win: false);

        // Both checks run. A modifier destination can also be a catalog row: an owner may record a
        // use of bare Ctrl, and the modifier rule alone would hide their own record.
        string? modifierLabel = ModifierLabel(canonicalDestination);

        if (match is null && modifierLabel is null)
            return null;

        List<string> sentences = [$"This hotkey makes {sourceComboLabel} act as {canonicalDestination}."];

        if (match is not null)
        {
            if (match.WarningText is { Length: > 0 } overrideText)
                sentences.Add(overrideText);
            else
                sentences.AddRange(UseSentences(match, canonicalDestination));
        }

        if (modifierLabel is not null)
            sentences.Add($"Shortcuts that use {modifierLabel} may also respond when you hold {sourceComboLabel}.");

        // The only closing that still holds on this side. The override closing would be wrong here,
        // and "may also respond" already hedges, so everything else ends without one.
        if (match is not null && match.Uses.Any(u => u.Protection == ShortcutProtection.Protected))
            sentences.Add(ProtectedClosing);

        return string.Join(" ", sentences);
    }

    // The notice's name for a modifier key, or null when the key is not a modifier.
    private static string? ModifierLabel(string canonicalKey) =>
        s_modifierLabels.TryGetValue(canonicalKey, out string? label) ? label : null;

    // One sentence per thing the keys do, shared by the source notice and the destination notice.
    // Grouped by what the keys do, so two products doing the same thing share one sentence.
    private static List<string> UseSentences(KnownShortcutDto shortcut, string comboLabel)
    {
        List<string> sentences = [];

        foreach (IGrouping<(string Does, ShortcutScope Scope), ShortcutUseDto> group in
                 shortcut.Uses.GroupBy(u => (u.Does, u.Scope)))
        {
            string[] labels = [.. group.Select(u => u.UsedBy)];
            string subject = JoinLabels(labels);
            string verb = labels.Length == 1 ? "uses" : "use";
            string tail = group.Key.Scope == ShortcutScope.Foreground
                ? labels.Length == 1 ? ForegroundTailOne : ForegroundTailMany
                : ".";

            sentences.Add($"{subject} {verb} {comboLabel} to {group.Key.Does}{tail}");
        }

        return sentences;
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
