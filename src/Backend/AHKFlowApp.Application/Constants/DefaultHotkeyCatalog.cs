using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Constants;

/// <summary>
/// The curated sample hotkeys handed to a new user in development, shared by the lazy seed in
/// <c>ListHotkeysQueryHandler</c> and the explicit <c>SeedHotkeysCommandHandler</c> so the two can
/// never drift.
/// </summary>
/// <remarks>
/// Every row is a typed <see cref="HotkeyDefinition"/> plus its category names. Nothing here is
/// authored through <c>LegacyHotkeyDefinitionConverter</c>: this data has no legacy, so a
/// back-compat converter is the wrong authoring format for it. <c>LegacyHotkeyFixtures</c> is a
/// historical set of converter cases, not a mirror of this catalog — it guards the C# converter
/// against the migration's hand-written T-SQL, which is a separate concern.
/// The seed path bypasses validation, so every definition here must be correct by construction.
/// </remarks>
internal static class DefaultHotkeyCatalog
{
    /// <summary>One row per sample hotkey, in seed order.</summary>
    public static IReadOnlyList<DefaultHotkey> All { get; } =
    [
        // App launchers and lock. Run rows: RunTargetKind is Url only for an http(s) target.
        Run("Launch Windows Terminal", "T", "wt.exe",       RunTargetKind.Application, ["App Launcher"]),
        Run("Launch Notepad",          "N", "notepad.exe",  RunTargetKind.Application, ["App Launcher"]),
        Run("Launch File Explorer",    "E", "explorer.exe", RunTargetKind.Application, ["App Launcher"]),
        Run("Open default browser",    "B", "https://",     RunTargetKind.Url,         ["App Launcher"]),
        Run("Lock workstation",        "L", "rundll32.exe user32.dll,LockWorkStation",
            RunTargetKind.Application, ["App Launcher"]),

        // Window resize/snap on Ctrl+Alt+Arrow. These do NOT Send Win+Arrow: injected LWin (the
        // LLKHF_INJECTED flag + SendInput's atomic batch) is not reliably recognized by the shell's
        // Aero-Snap / Win-hotkey handler, so `Send("#{Left}")` fails to snap (design §2b). Native
        // window functions are deterministic. All four use the typed Window kind; the snap pair's
        // half-work-area WinMove block lives in the emitter, not here.
        Typed("Maximize window", "Up",   HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.Maximize),
        Typed("Minimize window", "Down", HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.Minimize),
        Typed("Snap window left",  "Left",  HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.SnapLeft),
        Typed("Snap window right", "Right", HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.SnapRight),

        // Fixed → Raw: legacy shape could not express a function call or block body (design §2).
        Raw("Reload AHK script",   true, true, false, false, "r", "Reload()", ["App Launcher"]),
        Raw("Insert today's date", true, true, false, false, "d",
            "SendText(FormatTime(A_Now, \"yyyy-MM-dd\"))", ["DateTime"]),
        Raw("Paste as plain text", true, false, true, false, "v", PastePlainTextBody, ["Code"]),

        // SendKeys — the only kind with no sample otherwise (SendText is shown via the date Raw body;
        // the snap rows dropped SendKeys for native window calls). A virtual media key and a modified
        // key sequence show what Send does that SendText/Run cannot. Neither uses Win, so neither trips
        // the Win-in-Send guardrail.
        SendKeys("Play / pause media",    "p", "{Media_Play_Pause}", ["App Launcher"]),
        SendKeys("Select to end of line", "k", "+{End}",             ["Code"]),

        // New typed kinds — one sample each for Disable, Remap, Window (design §3). Descriptions carry
        // the global-hijack disclosure for the risky F-key rows.
        Typed("Disable F1 Help (removes the Help key everywhere)", "F1", HotkeyActionKind.Disable,
            ["App Launcher"]),
        Typed("Mute volume (also steals F10, the menu-bar key)", "F10", HotkeyActionKind.Remap,
            ["App Launcher"], remapDest: "Volume_Mute"),
        Typed("Volume up (F9 no longer types normally)", "F9", HotkeyActionKind.Remap,
            ["App Launcher"], remapDest: "Volume_Up"),
        Typed("Keep window on top", "a", HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.ToggleAlwaysOnTop),
        // Restore, not another Minimize — Ctrl+Alt+Down already minimizes; this demoes a third WindowOp.
        Typed("Restore active window", "m", HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.Restore),
    ];

    // Mirrors the app's clipboard helper (ahk-v2-syntax.md "Clipboard delivery"): save the rich
    // clipboard, strip to plain text, paste, restore. A bare `A_Clipboard := A_Clipboard` would
    // strip the clipboard permanently, so the save/restore is mandatory (design §2).
    private const string PastePlainTextBody =
        "{\n" +
        "    saved := ClipboardAll()      ; preserve the original rich clipboard\n" +
        "    A_Clipboard := A_Clipboard   ; reading returns text-only, stripping formatting\n" +
        "    Send(\"^v\")\n" +
        "    Sleep(150)                   ; let the paste consume the clipboard first\n" +
        "    A_Clipboard := saved         ; restore the original formatting\n" +
        "    saved := \"\"\n" +
        "}";

    /// <summary>Run row on Ctrl+Alt, pinned all-profiles.</summary>
    private static DefaultHotkey Run(
        string description, string key, string target, RunTargetKind targetKind, string[] categories) =>
        new(new HotkeyDefinition(
                Description: description, Key: key, Ctrl: true, Alt: true, Shift: false, Win: false,
                ActionKind: HotkeyActionKind.Run, AppliesToAllProfiles: true,
                RunTarget: target, RunTargetKind: targetKind),
            categories);

    /// <summary>SendKeys row on Ctrl+Alt, pinned all-profiles.</summary>
    private static DefaultHotkey SendKeys(
        string description, string key, string content, string[] categories) =>
        new(new HotkeyDefinition(
                Description: description, Key: key, Ctrl: true, Alt: true, Shift: false, Win: false,
                ActionKind: HotkeyActionKind.SendKeys, AppliesToAllProfiles: true,
                SendKeysContent: content),
            categories);

    /// <summary>Raw-body row, pinned all-profiles.</summary>
    private static DefaultHotkey Raw(
        string description, bool ctrl, bool alt, bool shift, bool win,
        string key, string body, string[] categories) =>
        new(new HotkeyDefinition(
                Description: description, Key: key, Ctrl: ctrl, Alt: alt, Shift: shift, Win: win,
                ActionKind: HotkeyActionKind.Raw, AppliesToAllProfiles: true, Body: body),
            categories);

    /// <summary>Typed Disable/Remap/Window row, pinned all-profiles.</summary>
    private static DefaultHotkey Typed(
        string description, string key, HotkeyActionKind actionKind, string[] categories,
        bool ctrl = false, bool alt = false, bool shift = false, bool win = false,
        string? remapDest = null, WindowOp? windowOp = null) =>
        new(new HotkeyDefinition(
                Description: description, Key: key, Ctrl: ctrl, Alt: alt, Shift: shift, Win: win,
                ActionKind: actionKind, AppliesToAllProfiles: true,
                RemapDest: remapDest, WindowOp: windowOp),
            categories);
}

/// <summary>One sample hotkey: a pre-built typed definition plus its default-category names.</summary>
/// <param name="Definition">Typed hotkey definition seeded via <c>Hotkey.Create</c>.</param>
/// <param name="Categories">Names of the default categories the sample is linked to.</param>
internal sealed record DefaultHotkey(
    HotkeyDefinition Definition,
    string[] Categories);
