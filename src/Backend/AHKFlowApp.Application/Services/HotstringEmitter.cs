using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Single emission point for hotstring lines. Deterministic option order: X * ? C O T
/// — X leads for DateTime kind (T is never emitted for it); T trails for Text kind.
/// </summary>
internal static class HotstringEmitter
{
    public static string Emit(Hotstring hs) =>
        $":{BuildOptions(hs)}:{Escape(hs.Trigger)}::{BuildBody(hs)}";

    private static string BuildOptions(Hotstring hs)
    {
        bool isDateTime = hs.Kind == HotstringKind.DateTime;
        string options = isDateTime ? "X" : "";
        if (!hs.IsEndingCharacterRequired) options += "*";
        if (hs.IsTriggerInsideWord) options += "?";
        if (hs.IsCaseSensitive) options += "C";
        if (hs.OmitEndingCharacter && hs.IsEndingCharacterRequired) options += "O"; // O is meaningless with *
        if (!isDateTime) options += "T"; // Text kind always emits literally (WYSIWYG) — resolved decision D1
        return options;
    }

    private static string BuildBody(Hotstring hs) =>
        hs.Kind == HotstringKind.DateTime ? BuildDateTimeBody(hs) : Escape(hs.Replacement);

    private static string BuildDateTimeBody(Hotstring hs)
    {
        // DateTimeFormat is embedded raw (no escaping) because it has already passed a
        // server-side whitelist regex before reaching the emitter — validation lives elsewhere.
        string nowExpression = hs.DateOffsetAmount is int amount && hs.DateOffsetUnit is DateOffsetUnit unit
            ? $"DateAdd(A_Now, {amount}, \"{unit}\")"
            : "A_Now";
        return $"SendText(FormatTime({nowExpression}, \"{hs.DateTimeFormat}\"))";
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
