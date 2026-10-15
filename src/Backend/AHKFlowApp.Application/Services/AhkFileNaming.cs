using System.Text;

namespace AHKFlowApp.Application.Services;

public static class AhkFileNaming
{
    private const int MaxStemLength = 64;
    private const string EmptyFallback = "profile";

    /// <summary>
    /// Turns a profile name into a file-name stem. Every run of unsafe characters becomes one
    /// underscore. Only ASCII letters, digits, <c>.</c> and <c>-</c> survive. This is the only copy
    /// of the rule: the UI and the CLI both save a script under the name the API sends.
    /// </summary>
    /// <remarks>
    /// Leading underscores are trimmed before the cut to 64 characters, and trailing underscores
    /// after it. Trimming the end before the cut can leave a trailing underscore: a long name may
    /// collapse to text whose 64th character is an underscore, which the earlier trim never saw.
    /// Trimming the start first keeps as many real characters as fit.
    /// </remarks>
    public static string ToSafeStem(string profileName)
    {
        if (string.IsNullOrEmpty(profileName))
            return EmptyFallback;

        StringBuilder sb = new(profileName.Length);
        bool prevUnderscore = false;
        foreach (char c in profileName)
        {
            bool safe = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '-';
            if (safe)
            {
                sb.Append(c);
                prevUnderscore = false;
            }
            else if (!prevUnderscore)
            {
                sb.Append('_');
                prevUnderscore = true;
            }
        }

        string collapsed = sb.ToString().TrimStart('_');
        string truncated = collapsed.Length > MaxStemLength
            ? collapsed[..MaxStemLength]
            : collapsed;
        string trimmed = truncated.TrimEnd('_');

        return trimmed.Length == 0 ? EmptyFallback : trimmed;
    }

    public static string FileName(string profileName) =>
        $"ahkflow_{ToSafeStem(profileName)}.ahk";
}
