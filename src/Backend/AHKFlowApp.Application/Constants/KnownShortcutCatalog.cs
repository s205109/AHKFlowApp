using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Constants;

/// <param name="UsedBy">What uses the combination — "Windows", "Chrome", or an owner's own label.</param>
/// <param name="Protection">How hard the keys are to take over.</param>
/// <param name="Scope">Whether the use fires anywhere, or only in front.</param>
/// <param name="Does">Lowercase verb phrase completing "&lt;UsedBy&gt; uses &lt;combo&gt; to …".</param>
/// <param name="EvidenceUrl">Pinned page proving this use. One per use; a use without one does not ship.</param>
/// <param name="EvidenceCheckedOn">Date the pinned page was last read.</param>
internal sealed record ShortcutUse(
    string UsedBy,
    ShortcutProtection Protection,
    ShortcutScope Scope,
    string Does,
    string EvidenceUrl,
    DateOnly EvidenceCheckedOn);

/// <param name="Id">Stable, never reused. Format "windows.file-explorer".</param>
/// <param name="Key">Canonical key from <see cref="HotkeyKeys"/>.</param>
/// <param name="Ctrl">True when the combination needs Ctrl.</param>
/// <param name="Alt">True when the combination needs Alt.</param>
/// <param name="Shift">True when the combination needs Shift.</param>
/// <param name="Win">True when the combination needs the Windows key.</param>
/// <param name="Uses">Everything that uses this combination. At least one.</param>
/// <param name="WarningText">
/// Optional override. Warning text is normally composed from the uses; this is only for rows
/// where the composed sentence reads badly. Null for every row shipped in this release.
/// </param>
internal sealed record KnownShortcut(
    string Id,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    IReadOnlyList<ShortcutUse> Uses,
    string? WarningText = null);

/// <summary>
/// The curated list of shortcuts something outside AHKFlow already uses. Curation is the whole
/// product here: no user-mode API lists another process's hotkeys, so nothing is detected at
/// runtime (design §1). Every row is pinned to a public page and dated, so the list can be
/// re-checked by diffing that page.
/// </summary>
/// <remarks>
/// No value promises a runtime outcome. AutoHotkey documents overriding Windows hotkeys as a
/// feature, and a low-level keyboard hook installed earlier can swallow a keystroke outright,
/// so the warning says what else uses the keys — never what will happen.
/// </remarks>
internal static class KnownShortcutCatalog
{
    private const string WindowsUrl =
        "https://support.microsoft.com/en-us/windows/keyboard-shortcuts-in-windows-dcc61a57-8ff0-cffe-9796-cb9706c75eec";

    private const string WinlogonUrl =
        "https://learn.microsoft.com/en-us/windows/win32/secauthn/responsibilities-of-winlogon";

    private const string WinLockUrl =
        "https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-desktop/win-key-remains-held-after-pressing-ctrl-win-l-in-remote-session";

    private static readonly DateOnly s_checkedOn = new(2026, 7, 29);

    /// <summary>One row per combination, in design §3 order. Windows only in this release.</summary>
    /// <remarks>
    /// Letter keys are stored lowercase because that is what <see cref="HotkeyKeys"/> canonicalizes
    /// them to. Matching ignores case, so the stored spelling is a storage rule, not a display one.
    /// </remarks>
    public static IReadOnlyList<KnownShortcut> All { get; } =
    [
        // ---- Windows. Every row is Global and UsedBy "Windows". ----
        // The two Protected rows come first: they are the only rows with a Microsoft source
        // stating Windows itself handles the keys.
        Windows("windows.secure-attention", "Delete", "show the security screen",
            ctrl: true, alt: true, win: false,
            protection: ShortcutProtection.Protected, evidenceUrl: WinlogonUrl),
        Windows("windows.lock", "l", "lock the computer",
            protection: ShortcutProtection.Protected, evidenceUrl: WinLockUrl),

        // Win + letter.
        Windows("windows.action-center", "a", "open the action center"),
        Windows("windows.copilot", "c", "open Copilot"),
        Windows("windows.show-desktop", "d", "show and hide the desktop"),
        Windows("windows.file-explorer", "e", "open File Explorer"),
        Windows("windows.feedback-hub", "f", "open Feedback Hub"),
        Windows("windows.game-bar", "g", "open Game Bar"),
        Windows("windows.voice-dictation", "h", "open voice dictation"),
        Windows("windows.settings", "i", "open Settings"),
        Windows("windows.recall", "j", "open Recall"),
        Windows("windows.cast", "k", "open Cast"),
        Windows("windows.minimize-all", "m", "minimize all windows"),
        Windows("windows.notification-center", "n", "open notification center and calendar"),
        Windows("windows.lock-orientation", "o", "lock device orientation"),
        Windows("windows.project", "p", "open presentation display modes"),
        Windows("windows.search-q", "q", "open search"),
        Windows("windows.run", "r", "open the Run dialog"),
        Windows("windows.search-s", "s", "open search"),
        Windows("windows.accessibility", "u", "open Accessibility settings"),
        Windows("windows.clipboard-history", "v", "open clipboard history"),
        Windows("windows.widgets", "w", "open Widgets"),
        Windows("windows.quick-link", "x", "open the Quick Link menu"),
        Windows("windows.mixed-reality", "y", "switch to Windows Mixed Reality"),
        Windows("windows.snap-layouts", "z", "open snap layouts"),

        // Win + named key.
        Windows("windows.task-view", "Tab", "open Task View"),
        Windows("windows.close-magnifier", "Escape", "close Magnifier"),
        Windows("windows.about", "Pause", "open Settings to System > About"),
        Windows("windows.screenshot-file", "PrintScreen", "save a full-screen screenshot to a file"),
        Windows("windows.minimize-others", "Home", "minimize or restore all but the active window"),
        Windows("windows.maximize", "Up", "maximize the active window"),
        Windows("windows.minimize", "Down", "minimize the active window"),
        Windows("windows.snap-left", "Left", "snap the window left"),
        Windows("windows.snap-right", "Right", "snap the window right"),
        Windows("windows.input-next", "Space", "switch to the next input language or layout"),

        // Win + Shift.
        Windows("windows.screenshot-region", "s", "capture a screen region to the clipboard", shift: true),
        Windows("windows.restore-minimized", "m", "restore minimized windows", shift: true),
        Windows("windows.record-region", "r", "record a screen region", shift: true),
        Windows("windows.cycle-notifications", "v", "cycle through notifications", shift: true),
        Windows("windows.monitor-left", "Left", "move the window to the monitor on the left", shift: true),
        Windows("windows.monitor-right", "Right", "move the window to the monitor on the right", shift: true),
        Windows("windows.stretch-vertical", "Up", "stretch the window top to bottom", shift: true),
        Windows("windows.restore-snapped", "Down", "restore a snapped or maximized window", shift: true),
        Windows("windows.uwp-fullscreen", "Enter", "make a UWP app full screen", shift: true),
        Windows("windows.tip-focus", "a", "focus a Windows tip", shift: true),
        Windows("windows.input-previous", "Space", "switch to the previous input language or layout", shift: true),

        // Win + Ctrl. windows.wake-display carries Shift as well, so it lives here.
        Windows("windows.color-filters", "c", "toggle color filters", ctrl: true),
        Windows("windows.narrator", "Enter", "open Narrator", ctrl: true),
        Windows("windows.find-devices", "f", "search for devices on a network", ctrl: true),
        Windows("windows.quick-assist", "q", "open Quick Assist", ctrl: true),
        Windows("windows.sound-output", "v", "open the sound output page", ctrl: true),
        Windows("windows.wake-display", "b", "wake the device when the screen is blank", ctrl: true, shift: true),
        Windows("windows.input-recent", "Space", "switch to the previous input option", ctrl: true),

        // Win + Alt.
        Windows("windows.hdr", "b", "toggle high dynamic range", alt: true),
        Windows("windows.desktop-clock", "d", "show and hide date and time on the desktop", alt: true),
        Windows("windows.voice-keyboard-focus", "h", "focus the keyboard during voice typing", alt: true),
        Windows("windows.mute-mic", "k", "mute or unmute the microphone", alt: true),
        Windows("windows.snap-top", "Up", "snap the window to the top half", alt: true),
        Windows("windows.snap-bottom", "Down", "snap the window to the bottom half", alt: true),

        // No-Win Windows rows.
        Windows("windows.task-manager", "Escape", "open Task Manager", ctrl: true, shift: true, win: false),
        Windows("windows.start-menu", "Escape", "open the Start menu", ctrl: true, win: false),
        Windows("windows.switch-windows", "Tab", "switch between open windows", alt: true, win: false),
        Windows("windows.app-thumbnails", "Tab", "view thumbnails of all open apps", ctrl: true, alt: true, win: false),
        Windows("windows.cycle-windows", "Escape", "cycle windows in the order opened", alt: true, win: false),
        Windows("windows.close-window", "F4", "close the active window", alt: true, win: false),
        Windows("windows.window-menu", "Space", "open the active window's context menu", alt: true, win: false),
        Windows("windows.show-password", "F8", "show the password on the sign-in screen", alt: true, win: false),

        // Browser rows (design §3) are Stage 2 — see the Stage 2 plan. They need the ignore
        // mechanism before they are tolerable, because they cover 15 of 26 Ctrl+letter keys.
    ];

    // Win is the default modifier because most Windows rows use it; the no-Win rows pass win: false.
    private static KnownShortcut Windows(
        string id,
        string key,
        string does,
        bool ctrl = false,
        bool alt = false,
        bool shift = false,
        bool win = true,
        ShortcutProtection protection = ShortcutProtection.Normal,
        string evidenceUrl = WindowsUrl) =>
        new(id, key, ctrl, alt, shift, win,
        [
            new ShortcutUse("Windows", protection, ShortcutScope.Global, does, evidenceUrl, s_checkedOn),
        ]);
}
