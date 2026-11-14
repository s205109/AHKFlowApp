namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// A count with its noun, such as "1 hotstring" or "3 hotstrings". Only one takes the singular.
/// The caller passes both forms, because English plurals such as "categories" are not regular.
/// </summary>
internal static class CountWording
{
    public static string Of(int count, string singular, string plural) =>
        $"{count} {(count == 1 ? singular : plural)}";

    /// <summary>
    /// "2 hotstrings and 1 hotkey". A kind with a count of zero is left out, so the caller
    /// handles a total of zero itself.
    /// </summary>
    public static string HotstringsAndHotkeys(int hotstringCount, int hotkeyCount)
    {
        List<string> parts = [];
        if (hotstringCount > 0)
            parts.Add(Of(hotstringCount, "hotstring", "hotstrings"));
        if (hotkeyCount > 0)
            parts.Add(Of(hotkeyCount, "hotkey", "hotkeys"));

        return string.Join(" and ", parts);
    }
}
