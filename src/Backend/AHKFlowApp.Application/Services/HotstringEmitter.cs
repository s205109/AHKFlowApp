using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotstring lines. Deterministic option order: X * ? C O T
/// (X arrives with non-Text kinds in later phases).
/// </summary>
internal static class HotstringEmitter
{
    public static string Emit(Hotstring hs) =>
        $":{BuildOptions(hs)}:{Escape(hs.Trigger)}::{Escape(hs.Replacement)}";

    private static string BuildOptions(Hotstring hs)
    {
        string options = "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        if (hs.IsCaseSensitive) options += "C";
        if (hs.OmitEndingCharacter && hs.IsEndingCharacterRequired) options += "O"; // O is meaningless with *
        options += "T"; // Text kind always emits literally (WYSIWYG) — resolved decision D1
        return options;
    }

    // Keep every hotstring on one physical line and its trigger free of characters
    // AHK v2 would otherwise reinterpret (backtick, a whitespace-preceded ';'). Backtick
    // must be escaped first so later escapes are not double-escaped.
    private static string Escape(string value) =>
        value
            .Replace("`", "``")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t")
            .Replace(";", "`;");
}
