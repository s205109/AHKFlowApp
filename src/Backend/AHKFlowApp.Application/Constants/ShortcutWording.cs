using System.Text.RegularExpressions;

namespace AHKFlowApp.Application.Constants;

/// <summary>Wording rules every shortcut warning obeys, built-in and owner-written alike.</summary>
internal static partial class ShortcutWording
{
    /// <summary>
    /// Absolute claims a warning must never make. A shortcut warning says what else uses the keys;
    /// it never promises what will happen when they are pressed (<c>CONTEXT.md:99</c>).
    /// </summary>
    internal static readonly string[] BannedTerms =
        ["never", "will not", "cannot", "won't", "can't"];

    /// <summary>True if the text makes a claim about what will or will not happen.</summary>
    internal static bool MakesAbsoluteClaim(string text) => AbsoluteClaim().IsMatch(text);

    // Word boundaries, not substrings: "whenever" contains "never" and is perfectly good English
    // for a shortcut description. \b sits between a word character and a non-word character, and
    // there is none inside "whenever", so that word passes while a bare "never" does not.
    [GeneratedRegex(@"\b(never|will not|cannot|won't|can't)\b", RegexOptions.IgnoreCase)]
    private static partial Regex AbsoluteClaim();
}
