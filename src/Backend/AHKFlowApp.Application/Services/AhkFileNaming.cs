using System.Text;

namespace AHKFlowApp.Application.Services;

public static class AhkFileNaming
{
    private const int MaxStemLength = 64;
    private const string EmptyFallback = "profile";

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

        string collapsed = sb.ToString().Trim('_');
        if (collapsed.Length == 0)
            return EmptyFallback;

        return collapsed.Length > MaxStemLength
            ? collapsed[..MaxStemLength]
            : collapsed;
    }

    public static string FileName(string profileName) =>
        $"ahkflow_{ToSafeStem(profileName)}.ahk";
}
