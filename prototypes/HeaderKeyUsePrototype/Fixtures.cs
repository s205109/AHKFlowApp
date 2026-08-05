namespace HeaderKeyUsePrototype;

/// <summary>
/// PROTOTYPE — throwaway. Real header text, copied so the prototype needs no project reference.
/// Sources: DefaultProfileTemplates.cs:5-17 and HeaderPresetCatalog.cs:50-102.
/// The last three variants are hand-written cases the shipped catalog does not contain.
/// </summary>
public static class Fixtures
{
    public static readonly string[] VariantNames =
    [
        "default header only",
        "+ Caps Lock layer preset",
        "+ lock keys off preset",
        "+ hand-written CapsLock:: (no star)",
        "+ hand-written ^!c:: (has modifiers)",
        "+ hand-written LCtrl & RAlt:: (combination)",
    ];

    public static string Header(int variant) => variant switch
    {
        0 => DefaultHeader,
        1 => DefaultHeader + CapsLockLayerPreset,
        2 => DefaultHeader + LockKeysOffPreset,
        3 => DefaultHeader + HandWrittenPlainCapsLock,
        4 => DefaultHeader + HandWrittenModifierHotkey,
        5 => DefaultHeader + HandWrittenCombination,
        _ => DefaultHeader,
    };

    private const string DefaultHeader = """
        ; {ProfileName} — AHKFlowApp v{AppVersion}
        ; {HotstringCount} hotstrings, {HotkeyCount} hotkeys
        ; Generated {GeneratedAt:yyyy-MM-dd HH:mm}Z

        #Requires AutoHotkey v2.0
        #SingleInstance Force
        #Warn All, Off
        SendMode "Input"
        SetWorkingDir A_ScriptDir
        SetTitleMatchMode 2

        """;

    private const string CapsLockLayerPreset = """

        ; --- AHKFlow preset: capslock-modifier-layer ---
        ; Hold Caps Lock to press Ctrl, Alt and Shift together.
        ; Set your hotkeys to Ctrl+Alt+Shift to use this layer.
        ; Caps Lock no longer switches capitals on or off.
        SetCapsLockState "AlwaysOff"

        *CapsLock::
        {
            SetKeyDelay -1
            Send "{Blind}{LCtrl DownR}{LAlt DownR}{LShift DownR}"
        }

        *CapsLock up::
        {
            SetKeyDelay -1
            Send "{Blind}{LCtrl Up}{LAlt Up}{LShift Up}"
        }
        ; --- end capslock-modifier-layer ---

        """;

    private const string LockKeysOffPreset = """

        ; --- AHKFlow preset: lock-keys-off ---
        ; Keep Num Lock, Caps Lock and Scroll Lock switched off at all times.
        SetNumLockState "AlwaysOff"
        SetCapsLockState "AlwaysOff"
        SetScrollLockState "AlwaysOff"
        ; --- end lock-keys-off ---

        """;

    private const string HandWrittenPlainCapsLock = """

        CapsLock::Send "hello"

        """;

    private const string HandWrittenModifierHotkey = """

        ^!c::Run "calc.exe"

        """;

    private const string HandWrittenCombination = """

        LCtrl & RAlt::MsgBox "AltGr"

        """;

    public static readonly string[] FooterVariantNames =
    [
        "empty footer",
        "footer with *ScrollLock::",
        "footer with the Caps Lock layer too",
    ];

    public static string Footer(int variant) => variant switch
    {
        1 => """

            *ScrollLock::Run "notepad"

            """,
        2 => CapsLockLayerPreset,
        _ => "",
    };

    /// <summary>
    /// Stands in for the key registry. Only the names this prototype drives through are listed.
    /// The real app calls IHotkeyKeyCatalog.CanonicalizeAsync (IHotkeyKeyCatalog.cs:31), which
    /// hands back the input unchanged for a name the registry does not know — so this does too.
    /// </summary>
    private static readonly Dictionary<string, string> s_canonical = new(StringComparer.OrdinalIgnoreCase)
    {
        ["CapsLock"] = "CapsLock",
        ["Capital"] = "CapsLock",
        ["ScrollLock"] = "ScrollLock",
        ["NumLock"] = "NumLock",
        ["LCtrl"] = "LCtrl",
        ["RAlt"] = "RAlt",
        ["C"] = "C",
        ["F1"] = "F1",
    };

    public static string Canonicalize(string key) =>
        s_canonical.TryGetValue(key, out string? canonical) ? canonical : key;
}
