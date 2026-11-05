namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// The confirmation and result text of a bulk delete. The desktop and mobile paths of the
/// Hotstrings and Hotkeys pages all use it, so a delete of one item reads as singular everywhere.
/// </summary>
internal static class BulkDeleteWording
{
    public static string Title(int count, string singular, string plural) =>
        $"Delete {(count == 1 ? singular : plural)}?";

    public static string Message(int count, string singular, string plural) =>
        $"Delete {CountWording.Of(count, singular, plural)}? "
        + $"You can restore {(count == 1 ? "it" : "them")} from the Recycle Bin.";

    public static string ResultMessage(int deleted, int missing, string singular, string plural)
    {
        string result = $"Deleted {CountWording.Of(deleted, singular, plural)}.";
        return missing > 0
            ? $"{result} {missing} {(missing == 1 ? "was" : "were")} already gone."
            : result;
    }
}
