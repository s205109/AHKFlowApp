using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using HotkeyAction = AHKFlowApp.Application.Services.LegacyHotkeyDefinitionConverter.HotkeyAction;

namespace AHKFlowApp.Application.Constants;

/// <summary>
/// The curated sample hotkeys handed to a new user in development, shared by the lazy seed in
/// <c>ListHotkeysQueryHandler</c> and the explicit <c>SeedHotkeysCommandHandler</c> so the two can
/// never drift.
/// </summary>
/// <remarks>
/// Mixed shape: each row is a pre-built <see cref="HotkeyDefinition"/> plus its category names. The
/// legacy-shaped subset (app launchers, lock) is built through <see cref="Legacy"/>, which runs the
/// row through <c>LegacyHotkeyDefinitionConverter.FromLegacy</c> — the same transform the EF data
/// migration applies to real legacy rows. That launcher/lock subset (unchanged emitted output) is
/// mirrored by <c>LegacyHotkeyFixtures</c> for the migration-parity test; the window rows and the
/// fixed/new rows are typed or Raw, so they are excluded from that mirror. The seed path bypasses
/// validation, so every typed definition here must be correct by construction.
/// </remarks>
internal static class DefaultHotkeyCatalog
{
    /// <summary>One row per sample hotkey, in seed order.</summary>
    public static IReadOnlyList<DefaultHotkey> All { get; } =
    [
        // Legacy launchers + lock — unchanged output, mirrored by LegacyHotkeyFixtures.
        Legacy("Launch Windows Terminal", true, true, false, false, "T", HotkeyAction.Run, "wt.exe",       ["App Launcher"]),
        Legacy("Launch Notepad",          true, true, false, false, "N", HotkeyAction.Run, "notepad.exe",  ["App Launcher"]),
        Legacy("Launch File Explorer",    true, true, false, false, "E", HotkeyAction.Run, "explorer.exe", ["App Launcher"]),
        Legacy("Open default browser",    true, true, false, false, "B", HotkeyAction.Run, "https://",     ["App Launcher"]),
        Legacy("Lock workstation",        true, true, false, false, "L", HotkeyAction.Run, "rundll32.exe user32.dll,LockWorkStation", ["App Launcher"]),

        // Window resize/snap on Ctrl+Alt+Arrow. These do NOT Send Win+Arrow: injected LWin (the
        // LLKHF_INJECTED flag + SendInput's atomic batch) is not reliably recognized by the shell's
        // Aero-Snap / Win-hotkey handler, so `Send("#{Left}")` fails to snap (design §2b). Native
        // window functions are deterministic. Max/Min use the typed Window kind; snap L/R need a
        // half-work-area WinMove that no WindowOp expresses, so they are Raw bodies.
        Typed("Maximize window", "Up",   HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.Maximize),
        Typed("Minimize window", "Down", HotkeyActionKind.Window, ["Window Management"],
            ctrl: true, alt: true, windowOp: WindowOp.Minimize),
        Raw("Snap window left",  true, true, false, false, "Left",  SnapLeftBody,  ["Window Management"]),
        Raw("Snap window right", true, true, false, false, "Right", SnapRightBody, ["Window Management"]),

        // Fixed → Raw: legacy shape could not express a function call or block body (design §2).
        Raw("Reload AHK script",   true, true, false, false, "r", "Reload()", ["App Launcher"]),
        Raw("Insert today's date", true, true, false, false, "d",
            "SendText(FormatTime(A_Now, \"yyyy-MM-dd\"))", ["DateTime"]),
        Raw("Paste as plain text", true, false, true, false, "v", PastePlainTextBody, ["Code"]),

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

    // Snap the active window to the left/right half of the primary monitor's work area (excludes the
    // taskbar). WinRestore first so a maximized window can be moved. `//` is AHK integer division.
    // Deterministic native positioning — see the resize/snap comment above for why Send("#{Left}") is
    // not used. Primary monitor keeps the sample readable; a real multi-monitor snap would resolve the
    // window's own monitor first.
    private const string SnapLeftBody =
        "{\n" +
        "    WinRestore(\"A\")\n" +
        "    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)\n" +
        "    WinMove(l, t, (r - l) // 2, b - t, \"A\")\n" +
        "}";

    private const string SnapRightBody =
        "{\n" +
        "    WinRestore(\"A\")\n" +
        "    MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)\n" +
        "    WinMove(l + (r - l) // 2, t, (r - l) // 2, b - t, \"A\")\n" +
        "}";

    /// <summary>Legacy-shaped row: converted to typed columns at build time, pinned all-profiles.</summary>
    private static DefaultHotkey Legacy(
        string description, bool ctrl, bool alt, bool shift, bool win,
        string key, HotkeyAction action, string parameters, string[] categories) =>
        new(LegacyHotkeyDefinitionConverter.FromLegacy(
                description, key, ctrl, alt, shift, win, action, parameters,
                appliesToAllProfiles: true),
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
