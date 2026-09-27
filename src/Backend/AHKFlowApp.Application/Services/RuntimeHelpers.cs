using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// The Runtime helpers a Profile script can carry, and the one place that decides which of them a
/// set of hotstrings and hotkeys needs. A Runtime helper is an AutoHotkey function that the app
/// writes once into a Profile script, because some generated definitions call it.
/// </summary>
/// <remarks>
/// <see cref="AhkScriptGenerator"/> and both preview handlers ask <see cref="NeededBy"/>, so a
/// Profile script and its previews always carry the same helpers.
/// </remarks>
internal static class RuntimeHelpers
{
    public const string ClipboardPasteName = "AhkFlow_PasteReplacement";

    // Clipboard Delivery calls this helper. It saves the user's clipboard, pastes the text, and
    // restores the clipboard. The raw string takes its line breaks from this file, and
    // .gitattributes checks .cs files out with CRLF, so the helper's lines end in CRLF. The
    // function name comes from ClipboardPasteName, so the name exists once.
    public const string ClipboardPasteFunction =
        $$"""
        {{ClipboardPasteName}}(text, endChar := "") {
            saved := ClipboardAll()
            A_Clipboard := text
            if !ClipWait(1) {
                A_Clipboard := saved
                return
            }
            Send "^v"
            Sleep 150
            A_Clipboard := saved
            saved := ""
            if (endChar != "")
                SendText endChar
        }
        """;

    /// <summary>
    /// The text of every Runtime helper that the app's emitted definitions call, in script order.
    /// The list is empty when no emitted definition calls a helper.
    /// </summary>
    /// <remarks>
    /// Only the calls the emitters write count. A Raw definition keeps the text the user typed, and
    /// this method does not read that text for helper calls.
    /// No Hotkey Action calls a Runtime helper yet, because the window-snap body stays inline in
    /// <see cref="HotkeyEmitter"/>. The hotkeys are part of the question anyway, so a future hotkey
    /// helper changes this method and no caller.
    /// </remarks>
    public static IReadOnlyList<string> NeededBy(IEnumerable<Hotstring> hotstrings, IEnumerable<Hotkey> hotkeys)
    {
        List<string> needed = [];
        if (hotstrings.Any(h => HotstringEmitter.ResolveEffectiveDelivery(h) == HotstringDelivery.ClipboardPaste))
            needed.Add(ClipboardPasteFunction);

        return needed;
    }
}
