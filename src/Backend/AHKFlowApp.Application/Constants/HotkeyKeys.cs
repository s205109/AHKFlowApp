using System.Text.RegularExpressions;

namespace AHKFlowApp.Application.Constants;

/// <summary>Roles a registry key may legally play. Each role has its own AHK grammar.</summary>
[Flags]
internal enum HotkeyKeyRoles
{
    None = 0,

    /// <summary>Usable as the activating key of a hotkey.</summary>
    HotkeyKey = 1,

    /// <summary>Usable as the prefix of a custom combination (<c>a &amp; b</c>).</summary>
    ComboPrefix = 2,

    /// <summary>Usable inside a <c>Send</c> token.</summary>
    SendToken = 4,

    /// <summary>Usable as the source of a remap.</summary>
    RemapSource = 8,

    /// <summary>Usable as the destination of a remap.</summary>
    RemapDest = 16,

    All = HotkeyKey | ComboPrefix | SendToken | RemapSource | RemapDest,
}

/// <param name="Canonical">The single spelling persisted and emitted.</param>
/// <param name="Group">Picker grouping label.</param>
/// <param name="Roles">Which roles this key may play.</param>
/// <param name="RequiresBracesInSend">
/// True for named keys, which AHK requires be braced inside a Send string
/// (<c>{Volume_Up}</c>). False for single printable characters, which are bare (<c>c</c>).
/// </param>
internal sealed record HotkeyKeyEntry(
    string Canonical,
    string Group,
    HotkeyKeyRoles Roles,
    bool RequiresBracesInSend);

/// <summary>
/// Canonical registry of hotkey keys — the single source shared by validation and (from
/// Wave 1) the key picker.
/// </summary>
/// <remarks>
/// Scope is a curated subset, not AHK's full key list, with <c>vkNN</c>/<c>scNNN</c> as the
/// documented escape hatch for anything omitted. Joystick keys are excluded deliberately:
/// AHK does not support modifier prefixes such as <c>^</c> and <c>+</c> on joystick hotkeys,
/// and the axis names (JoyX, JoyY, JoyPOV, …) cannot be hotkeys at all — both contradict the
/// modifier-flag model. Mouse and wheel entries arrive in Wave 2 alongside their picker group.
/// </remarks>
internal static class HotkeyKeys
{
    public const string GroupLetterOrDigit = "Letters & digits";
    public const string GroupFunction = "Function keys";
    public const string GroupNamed = "Named & cursor";
    public const string GroupNumpad = "Numpad";
    public const string GroupMedia = "Media & browser";
    public const string GroupModifiers = "Modifiers";

    // A hotkey definition accepts vkNN or scNNN, but never the combined vkNNscNNN form —
    // AHK raises an error for "vk1Bsc001::". Combining is supported only by Send,
    // GetKeyName, GetKeyVK, GetKeySC and A_MenuMaskKey.
    // Anchored with \A and \z, not ^ and $: .NET's $ also matches before a trailing newline,
    // so "vk1\n" would pass and split the emitted left-hand side across two script lines.
    private static readonly Regex s_virtualKey =
        new(@"\Avk[0-9a-f]{1,2}\z", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex s_scanCode =
        new(@"\Asc[0-9a-f]{1,3}\z", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly string[] s_namedKeys =
    [
        "Enter", "Escape", "Space", "Tab", "Backspace", "Delete", "Insert",
        "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right",
        "CapsLock", "ScrollLock", "PrintScreen", "Pause", "AppsKey",
    ];

    private static readonly string[] s_numpadKeys =
    [
        "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
        "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
        "NumpadDot", "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv",
        "NumpadEnter", "NumLock",
    ];

    private static readonly string[] s_mediaKeys =
    [
        "Volume_Up", "Volume_Down", "Volume_Mute",
        "Media_Play_Pause", "Media_Stop", "Media_Next", "Media_Prev",
        "Browser_Back", "Browser_Forward", "Browser_Refresh", "Browser_Stop",
        "Browser_Search", "Browser_Favorites", "Browser_Home",
        "Launch_Mail", "Launch_Media",
    ];

    // Modifier keys. They ARE valid hotkey keys (Ctrl::), valid Send tokens ({LWin}), and valid
    // remap source and destination (CapsLock::Ctrl, RAlt::RButton). Deferred from W0 because remap
    // — their only reason to exist as picker entries — had no action kind until W1.
    private static readonly string[] s_modifierKeys =
    [
        "Ctrl", "Alt", "Shift", "LWin", "RWin",
        "LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift",
    ];

    // Accepted spellings that resolve to a canonical entry. AHK accepts several of these
    // itself; persisting one spelling keeps duplicate detection honest, so that "Esc" and
    // "Escape" cannot become two rows for the same physical binding.
    private static readonly Dictionary<string, string> s_aliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Esc"] = "Escape",
        ["Return"] = "Enter",
        ["Del"] = "Delete",
        ["Ins"] = "Insert",
        ["BS"] = "Backspace",
        ["Break"] = "Pause",
        ["PgDown"] = "PgDn",
        ["PageUp"] = "PgUp",
        ["PageDown"] = "PgDn",
        ["Control"] = "Ctrl",
        ["Windows"] = "LWin",
        ["Win"] = "LWin",
    };

    private static readonly IReadOnlyList<HotkeyKeyEntry> s_all = BuildRegistry();

    private static readonly Dictionary<string, HotkeyKeyEntry> s_byName =
        s_all.ToDictionary(e => e.Canonical, StringComparer.OrdinalIgnoreCase);

    public static IReadOnlyList<HotkeyKeyEntry> All => s_all;

    /// <summary>
    /// Resolves any accepted spelling to the single canonical form, or returns false if the
    /// value is neither a registry key nor a well-formed <c>vk</c>/<c>sc</c> code.
    /// </summary>
    /// <remarks>
    /// Canonicalization covers all three axes the duplicate check depends on: alias
    /// (<c>Esc</c> → <c>Escape</c>), case (<c>F5</c>), and code width — <c>vk1</c> → <c>vk01</c>,
    /// <c>sc1</c> → <c>sc001</c>. Without the padding, <c>vk1</c> and <c>vk01</c> name the same
    /// physical key but survive as two rows.
    /// A zero code (<c>vk0</c>, <c>sc000</c>) is rejected — it names no key.
    /// Surrounding whitespace is <em>not</em> trimmed: it is rejected, matching the existing
    /// "Key must not have leading or trailing whitespace." rule this replaces.
    /// </remarks>
    public static bool TryCanonicalize(string? key, out string canonical)
    {
        canonical = string.Empty;
        if (string.IsNullOrWhiteSpace(key))
            return false;

        if (s_aliases.TryGetValue(key, out string? aliased))
        {
            canonical = aliased;
            return true;
        }

        if (s_byName.TryGetValue(key, out HotkeyKeyEntry? entry))
        {
            canonical = entry.Canonical;
            return true;
        }

        if (s_virtualKey.IsMatch(key))
            return TryCanonicalizeCode(key, "vk", width: 2, out canonical);

        if (s_scanCode.IsMatch(key))
            return TryCanonicalizeCode(key, "sc", width: 3, out canonical);

        return false;
    }

    public static bool IsValidHotkeyKey(string? key) => TryCanonicalize(key, out _);

    /// <summary>Returns the registry entry for a canonical name. Throws if absent — callers pass
    /// names they already know are in the registry (tests, picker construction).</summary>
    public static HotkeyKeyEntry HotkeyKeyEntryByCanonical(string canonical) => s_byName[canonical];

    /// <summary>Accepted non-canonical spellings, keyed by alias (<c>Esc</c> → <c>Escape</c>).
    /// Read by the Migration A name-list generator, which must accept every spelling
    /// <see cref="TryCanonicalize"/> resolves — the migration itself never canonicalizes.</summary>
    public static IReadOnlyDictionary<string, string> Aliases => s_aliases;

    /// <summary>
    /// True if <paramref name="key"/> may be the source of a remap: a registry key carrying the
    /// <see cref="HotkeyKeyRoles.RemapSource"/> role, or a <c>vk</c>/<c>sc</c> code. Wheel keys
    /// (Wave 2) will carry the role cleared.
    /// </summary>
    public static bool IsValidRemapSource(string? key) => HasRole(key, HotkeyKeyRoles.RemapSource);

    /// <summary>
    /// True if <paramref name="key"/> may be the destination of a remap: a registry key carrying
    /// the <see cref="HotkeyKeyRoles.RemapDest"/> role, or a <c>vk</c>/<c>sc</c> code. Excludes
    /// <c>Pause</c> (collides with the built-in function — use <c>vk13</c>) and braced tokens.
    /// </summary>
    public static bool IsValidRemapDest(string? key) => HasRole(key, HotkeyKeyRoles.RemapDest);

    private static bool HasRole(string? key, HotkeyKeyRoles role)
    {
        if (!TryCanonicalize(key, out string canonical))
            return false;

        // vk/sc codes are not in s_byName; they satisfy any single-key role.
        if (!s_byName.TryGetValue(canonical, out HotkeyKeyEntry? entry))
            return true;

        return entry.Roles.HasFlag(role);
    }

    // Code zero names no key — AHK rejects "vk00::" and "sc000::" with "Invalid hotkey".
    // The digit-count regexes cannot express "hex, but not all zero", so the value is
    // checked here, after the shape matched and before padding.
    private static bool TryCanonicalizeCode(string key, string prefix, int width, out string canonical)
    {
        canonical = string.Empty;

        string digits = key[2..];
        if (digits.All(c => c == '0'))
            return false;

        canonical = prefix + digits.ToLowerInvariant().PadLeft(width, '0');
        return true;
    }

    private static List<HotkeyKeyEntry> BuildRegistry()
    {
        List<HotkeyKeyEntry> entries = [];

        for (char c = 'a'; c <= 'z'; c++)
            entries.Add(new(c.ToString(), GroupLetterOrDigit, HotkeyKeyRoles.All, RequiresBracesInSend: false));

        for (char c = '0'; c <= '9'; c++)
            entries.Add(new(c.ToString(), GroupLetterOrDigit, HotkeyKeyRoles.All, RequiresBracesInSend: false));

        for (int i = 1; i <= 24; i++)
            entries.Add(new($"F{i}", GroupFunction, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        foreach (string name in s_namedKeys)
            entries.Add(new(name, GroupNamed, RolesForNamed(name), RequiresBracesInSend: true));

        foreach (string name in s_numpadKeys)
            entries.Add(new(name, GroupNumpad, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        foreach (string name in s_mediaKeys)
            entries.Add(new(name, GroupMedia, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        foreach (string name in s_modifierKeys)
            entries.Add(new(name, GroupModifiers, HotkeyKeyRoles.All, RequiresBracesInSend: true));

        return entries;
    }

    // Pause is excluded as a remap destination: the name collides with AHK's built-in Pause
    // function, so a remap must target vk13 instead.
    private static HotkeyKeyRoles RolesForNamed(string name) =>
        name == "Pause"
            ? HotkeyKeyRoles.All & ~HotkeyKeyRoles.RemapDest
            : HotkeyKeyRoles.All;
}
