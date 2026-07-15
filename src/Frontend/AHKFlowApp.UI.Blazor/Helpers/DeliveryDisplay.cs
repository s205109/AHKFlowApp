using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>Single-sourced label/data-test for a Text hotstring's resolved delivery chip.</summary>
internal static class DeliveryDisplay
{
    public const string ClipboardDataTest = "clipboard-delivery";
    public const string HotstringDataTest = "hotstring-delivery";

    public static bool IsClipboard(HotstringDelivery effectiveDelivery) =>
        effectiveDelivery == HotstringDelivery.ClipboardPaste;

    public static string Label(HotstringDelivery effectiveDelivery) =>
        IsClipboard(effectiveDelivery) ? "Clipboard" : "Hotstring";

    public static string DataTest(HotstringDelivery effectiveDelivery) =>
        IsClipboard(effectiveDelivery) ? ClipboardDataTest : HotstringDataTest;
}
