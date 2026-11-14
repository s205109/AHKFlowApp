namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// The confirmation text of a category delete. It says how many hotstrings and hotkeys use the
/// category, because the delete removes the category from each of them. The items survive.
/// </summary>
internal static class CategoryDeleteWording
{
    public static string Message(string name, int hotstringCount, int hotkeyCount)
    {
        int total = hotstringCount + hotkeyCount;
        if (total == 0)
            return $"Delete \"{name}\"? No hotstrings or hotkeys use this category. This cannot be undone.";

        string subject = CountWording.HotstringsAndHotkeys(hotstringCount, hotkeyCount);
        string usage = total == 1
            ? $"{subject} uses this category. It is not deleted, but it loses this category."
            : $"{subject} use this category. They are not deleted, but they lose this category.";

        return $"Delete \"{name}\"? {usage} This cannot be undone.";
    }
}
