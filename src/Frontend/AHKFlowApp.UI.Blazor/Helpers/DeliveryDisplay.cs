using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>Single-sourced label/data-test for a Text hotstring's resolved delivery chip.</summary>
internal static class DeliveryDisplay
{
    public const string ClipboardDataTest = "clipboard-delivery";

    public static bool IsClipboard(HotstringDelivery effectiveDelivery) =>
        effectiveDelivery == HotstringDelivery.ClipboardPaste;

    /// <summary>Only reached from the Type tooltip now — the chip itself reports the kind, and
    /// keystroke delivery is the unremarkable default, so only clipboard gets a visual marker.</summary>
    public static string Label(HotstringDelivery effectiveDelivery) =>
        IsClipboard(effectiveDelivery) ? "Clipboard" : "Hotstring";
}
