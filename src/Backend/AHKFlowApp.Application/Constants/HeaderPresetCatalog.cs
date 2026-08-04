namespace AHKFlowApp.Application.Constants;

/// <summary>
/// The shipped header presets. Each body is AutoHotkey v2 text that an owner may append to a
/// Profile header; from that moment the text is theirs, and a later app version never rewrites
/// it. Every body is checked by <c>HeaderPresetCatalogTests</c> against two rules that would
/// otherwise break a generated script: no doubled braces, and no directive the default header
/// already emits.
/// </summary>
/// <remarks>
/// A preset exists only for whole-profile behaviour that a Hotstring or Hotkey row cannot
/// express. Anything a row already does stays a row, where it gets editing, history, and
/// conflict checks.
/// </remarks>
internal static class HeaderPresetCatalog
{
    public static IReadOnlyList<HeaderPreset> All { get; } =
    [
        new("capslock-modifier-layer",
            "Caps Lock works as Ctrl+Alt+Shift",
            "Hold Caps Lock to use hotkeys set up with Ctrl, Alt and Shift. This does not fire Ctrl+Alt hotkeys. Caps Lock stops switching capitals on and off.",
            "Keyboard layer",
            CapsLockLayerBody),

        new("lock-keys-off",
            "Keep Num Lock, Caps Lock and Scroll Lock off",
            "Holds all three lock keys off, so pressing one by accident changes nothing.",
            "Lock keys",
            LockKeysOffBody),

        new("pause-while-app-in-front",
            "Pause every shortcut while one application is in front",
            "Names one application, such as a game. While its window is in front, no hotstring or hotkey fires.",
            "Application behaviour",
            PauseWhileAppInFrontBody),

        new("hotstring-end-characters",
            "Choose which characters finish a hotstring",
            "Replaces AutoHotkey's default list of characters that fire a hotstring.",
            "Typing",
            HotstringEndCharactersBody),
    ];

    // The layer is Ctrl+Alt+Shift, not Ctrl+Alt: AutoHotkey treats AltGr as Left Ctrl + Right
    // Alt, so on an international layout a Ctrl+Alt layer fights the keyboard. Win is left out
    // because releasing it opens the Start menu. Ctrl+Alt+Shift does not fire the Ctrl+Alt
    // sample rows — an ordinary hotkey needs the exact modifier set — which is why the body
    // says so in a comment. The down/up pair is AutoHotkey's own translation of a remap
    // (docs/misc/Remap.htm, "each remapping is translated into a pair of hotkeys").
    private const string CapsLockLayerBody = """
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
        """;

    private const string LockKeysOffBody = """
        ; Keep Num Lock, Caps Lock and Scroll Lock switched off at all times.
        SetNumLockState "AlwaysOff"
        SetCapsLockState "AlwaysOff"
        SetScrollLockState "AlwaysOff"
        """;

    // A timer, not #HotIf. AhkScriptGenerator closes every window-context group with a bare
    // #HotIf (AhkScriptGenerator.cs:93-96), which would clear any context this header set.
    private const string PauseWhileAppInFrontBody = """
        ; Pause every hotstring and hotkey while one application is in front.
        ; Replace REPLACE-ME.exe with the application you want. Keep the ahk_exe part.
        SetTimer PauseWhileAppInFront, 500

        PauseWhileAppInFront()
        {
            static paused := false
            inFront := WinActive("ahk_exe REPLACE-ME.exe") != 0
            if (inFront != paused)
            {
                paused := inFront
                Suspend inFront
            }
        }
        """;

    private const string HotstringEndCharactersBody = """
        ; Choose which characters finish a hotstring.
        ; This list replaces AutoHotkey's default list for all hotstrings, not just the ones below it.
        ; `n is Enter, `s is Space, `t is Tab.
        ; This list matches AutoHotkey's own default, so it changes nothing unless you edit it.
        ; Remove characters you don't want, or add ones you do.
        #Hotstring EndChars -()[]{}:;'"/\,.?!`n`s`t
        """;
}

/// <summary>One shipped header preset.</summary>
/// <param name="Id">Stable kebab-case id, written into the marker comments.</param>
/// <param name="Name">Picker heading.</param>
/// <param name="Description">One line saying what the preset does.</param>
/// <param name="Tag">Picker grouping label.</param>
/// <param name="Body">The AutoHotkey text, without markers.</param>
internal sealed record HeaderPreset(
    string Id,
    string Name,
    string Description,
    string Tag,
    string Body);
