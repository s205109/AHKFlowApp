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

    private const string ChromeUrl =
        "https://support.google.com/chrome/answer/157179?co=GENIE.Platform%3DDesktop&hl=en-en";

    private const string EdgeUrl =
        "https://support.microsoft.com/en-US/edge/keyboard-shortcuts-in-microsoft-edge";

    private static readonly DateOnly s_checkedOn = new(2026, 7, 29);

    /// <summary>One row per combination, in design §3 order.</summary>
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

        // ---- Browsers. Every row is Foreground and Normal, and names both Chrome and Edge. ----
        // Each row is documented by Chrome and by Edge with the same meaning, so it carries two
        // uses with one evidence page each. Owners silence a use they do not want, per use.
        Browser("browser.new-tab", "t", "open a new tab", ctrl: true),
        Browser("browser.new-window", "n", "open a new window", ctrl: true),
        Browser("browser.close-tab", "w", "close the current tab", ctrl: true),
        Browser("browser.close-window", "w", "close the current window", ctrl: true, shift: true),
        Browser("browser.reopen-tab", "t", "reopen the last closed tab", ctrl: true, shift: true),
        Browser("browser.next-tab", "Tab", "switch to the next tab", ctrl: true),
        Browser("browser.previous-tab", "Tab", "switch to the previous tab", ctrl: true, shift: true),

        // Ctrl+1 through Ctrl+8 pick a tab by position. Ctrl+9 picks the last tab, whatever its
        // position, which is why it does not read "switch to tab 9".
        Browser("browser.tab-1", "1", "switch to tab 1", ctrl: true),
        Browser("browser.tab-2", "2", "switch to tab 2", ctrl: true),
        Browser("browser.tab-3", "3", "switch to tab 3", ctrl: true),
        Browser("browser.tab-4", "4", "switch to tab 4", ctrl: true),
        Browser("browser.tab-5", "5", "switch to tab 5", ctrl: true),
        Browser("browser.tab-6", "6", "switch to tab 6", ctrl: true),
        Browser("browser.tab-7", "7", "switch to tab 7", ctrl: true),
        Browser("browser.tab-8", "8", "switch to tab 8", ctrl: true),
        Browser("browser.tab-9", "9", "switch to the last tab", ctrl: true),

        Browser("browser.address-bar", "l", "focus the address bar", ctrl: true),
        Browser("browser.address-bar-alt", "d", "focus the address bar", alt: true),
        Browser("browser.search-e", "e", "search from the address bar", ctrl: true),
        Browser("browser.search-k", "k", "search from the address bar", ctrl: true),
        Browser("browser.devtools-i", "i", "open developer tools", ctrl: true, shift: true),
        Browser("browser.devtools-f12", "F12", "open developer tools"),
        Browser("browser.view-source", "u", "view the page source", ctrl: true),
        Browser("browser.history", "h", "open history", ctrl: true),
        Browser("browser.downloads", "j", "open downloads", ctrl: true),
        Browser("browser.bookmark", "d", "bookmark the current tab", ctrl: true),
        Browser("browser.bookmark-all", "d", "bookmark all open tabs", ctrl: true, shift: true),
        Browser("browser.bookmark-manager", "o", "open the bookmark manager", ctrl: true, shift: true),
        Browser("browser.bookmark-bar", "b", "show and hide the bookmarks bar", ctrl: true, shift: true),
        Browser("browser.find", "f", "find text on the page", ctrl: true),
        Browser("browser.find-next", "g", "go to the next find result", ctrl: true),
        Browser("browser.find-previous", "g", "go to the previous find result", ctrl: true, shift: true),
        Browser("browser.print", "p", "print the page", ctrl: true),
        Browser("browser.save-page", "s", "save the page", ctrl: true),
        Browser("browser.reload", "r", "reload the page", ctrl: true),
        Browser("browser.hard-reload", "r", "reload the page and skip the cache", ctrl: true, shift: true),
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

    // Two uses, one per browser, because the manifest rule is one evidence page per use. That also
    // lets an owner silence the Chrome use and keep the Edge one, which a single "Chrome, Edge"
    // label could not offer. Both are Foreground: a browser only answers these keys while in front.
    private static KnownShortcut Browser(
        string id,
        string key,
        string does,
        bool ctrl = false,
        bool alt = false,
        bool shift = false) =>
        new(id, key, ctrl, alt, shift, Win: false,
        [
            new ShortcutUse("Chrome", ShortcutProtection.Normal, ShortcutScope.Foreground, does, ChromeUrl, s_checkedOn),
            new ShortcutUse("Edge", ShortcutProtection.Normal, ShortcutScope.Foreground, does, EdgeUrl, s_checkedOn),
        ]);
}
