using AHKFlowApp.Application.Services;
using HotkeyAction = AHKFlowApp.Application.Services.LegacyHotkeyDefinitionConverter.HotkeyAction;

namespace AHKFlowApp.Application.Constants;

/// <summary>
/// The curated sample hotkeys handed to a new user in development, shared by the lazy seed in
/// <c>ListHotkeysQueryHandler</c> and the explicit <c>SeedHotkeysCommandHandler</c> so the two can
/// never drift.
/// </summary>
/// <remarks>
/// Deliberately expressed in the legacy <see cref="LegacyHotkeyDefinitionConverter.HotkeyAction"/> +
/// parameters shape. Both seed
/// loops run the rows through <c>LegacyHotkeyDefinitionConverter.FromLegacy</c>, the same transform the
/// EF data migration applies to real legacy rows, which keeps this the single authoritative copy of
/// the sample data that <c>LegacyHotkeyFixtures</c> mirrors for the migration parity test.
/// </remarks>
internal static class DefaultHotkeyCatalog
{
    /// <summary>One row per sample hotkey, in seed order.</summary>
    public static IReadOnlyList<DefaultHotkey> All { get; } =
    [
        new("Launch Windows Terminal", true,  true,  false, false, "T",     HotkeyAction.Run,  "wt.exe",       ["App Launcher"]),
        new("Launch Notepad",          true,  true,  false, false, "N",     HotkeyAction.Run,  "notepad.exe",  ["App Launcher"]),
        new("Launch File Explorer",    true,  true,  false, false, "E",     HotkeyAction.Run,  "explorer.exe", ["App Launcher"]),
        new("Open default browser",    true,  true,  false, false, "B",     HotkeyAction.Run,  "https://",     ["App Launcher"]),
        new("Maximize window",         false, true,  false, true,  "Up",    HotkeyAction.Send, "{Up}",         ["Window Management"]),
        new("Minimize window",         false, true,  false, true,  "Down",  HotkeyAction.Send, "{Down}",       ["Window Management"]),
        new("Snap window left",        false, true,  false, true,  "Left",  HotkeyAction.Send, "{Left}",       ["Window Management"]),
        new("Snap window right",       false, true,  false, true,  "Right", HotkeyAction.Send, "{Right}",      ["Window Management"]),
        new("Paste as plain text",     true,  false, true,  false, "V",     HotkeyAction.Send, "^v",           ["Code"]),
        new("Insert today's date",     true,  true,  false, false, "D",     HotkeyAction.Send, "{{date:yyyy-MM-dd}}", ["DateTime"]),
        new("Lock workstation",        true,  true,  false, false, "L",     HotkeyAction.Run,  "rundll32.exe user32.dll,LockWorkStation", ["App Launcher"]),
        new("Reload AHK script",       true,  true,  false, false, "R",     HotkeyAction.Run,  "Reload",       ["App Launcher"]),
    ];
}

/// <summary>One sample hotkey in the legacy action + parameters shape.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Key">Main key.</param>
/// <param name="Action">Legacy action kind, converted to the typed columns at seed time.</param>
/// <param name="Parameters">Legacy action payload, converted to the typed columns at seed time.</param>
/// <param name="Categories">Names of the default categories the sample is linked to.</param>
internal sealed record DefaultHotkey(
    string Description,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string Key,
    HotkeyAction Action,
    string Parameters,
    string[] Categories);
