namespace AHKFlowApp.UI.Blazor.Helpers;

/// <summary>
/// The text of a profile delete. An item that applies only to the deleted profile then applies to
/// no profile, so no script contains it. The confirmation says how many items that affects, and
/// the message after the delete repeats the count. The counts are items that apply only to this profile.
/// </summary>
internal static class ProfileDeleteWording
{
    public static string Confirmation(string name, int hotstringCount, int hotkeyCount)
    {
        int total = hotstringCount + hotkeyCount;
        if (total == 0)
            return $"Delete \"{name}\"? No hotstrings or hotkeys apply only to this profile. This cannot be undone.";

        string subject = CountWording.HotstringsAndHotkeys(hotstringCount, hotkeyCount);
        string effect = total == 1
            ? $"{subject} applies only to this profile. After the delete it applies to no profile, so no script contains it until you choose its profiles again."
            : $"{subject} apply only to this profile. After the delete they apply to no profile, so no script contains them until you choose their profiles again.";

        return $"Delete \"{name}\"? {effect} This cannot be undone.";
    }

    public static string Deleted(int hotstringCount, int hotkeyCount)
    {
        int total = hotstringCount + hotkeyCount;
        if (total == 0)
            return "Profile deleted.";

        string verb = total == 1 ? "applies" : "apply";
        return $"Profile deleted. {CountWording.HotstringsAndHotkeys(hotstringCount, hotkeyCount)} now {verb} to no profile.";
    }
}
