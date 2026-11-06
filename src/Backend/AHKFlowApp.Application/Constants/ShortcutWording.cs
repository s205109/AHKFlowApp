using System.Text.RegularExpressions;

namespace AHKFlowApp.Application.Constants;

/// <summary>Wording rules every shortcut warning obeys, built-in and owner-written alike.</summary>
internal static partial class ShortcutWording
{
    /// <summary>
    /// Absolute claims a warning must never make. A shortcut warning says what else uses the keys;
    /// it never promises what will happen when they are pressed
    /// (`CONTEXT.md:99`, "it never promises what will happen when the keys are pressed"). The list
    /// covers both directions: "will open" is refused as well as "will not open", and "always" as
    /// well as "never". One exception: "always" followed by "on top" is the name of the PowerToys
    /// utility Always On Top (https://learn.microsoft.com/windows/powertoys/always-on-top), so
    /// "toggle Always On Top" says what the keys do and passes.
    /// </summary>
    internal static readonly string[] BannedTerms =
        ["never", "always", "will", "'ll", "won't", "cannot", "can not", "can't"];

    /// <summary>True if the text makes a claim about what will or will not happen.</summary>
    internal static bool MakesAbsoluteClaim(string text) =>
        AbsoluteClaim().IsMatch(text.Replace('’', '\''));

    // Word boundaries, not substrings: "whenever" contains "never" and is perfectly good English
    // for a shortcut description. \b sits between a word character and a non-word character, and
    // there is none inside "whenever", so that word passes while a bare "never" does not.
    // The negative lookahead skips "always" when "on top" follows, with spaces or hyphens between.
    // The 'll arm has no leading \b: an apostrophe is a non-word character, so \b'll would need a
    // letter before it, and the bare term "'ll" would not match itself.
    // MakesAbsoluteClaim turns a typographic apostrophe (U+2019) into a straight one first, so
    // "won’t" and "it’ll" are refused like "won't" and "it'll".
    [GeneratedRegex(@"\b(?:never|always(?![\s-]+on[\s-]+top\b)|will|won't|cannot|can\s+not|can't)\b|'ll\b", RegexOptions.IgnoreCase)]
    private static partial Regex AbsoluteClaim();
}
