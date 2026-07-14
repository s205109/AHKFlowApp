using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Converts a legacy Script hotstring (body-only <c>Replacement</c> plus option flags) into the
/// equivalent verbatim Raw definition. The composed text is <em>byte-identical</em> to what the
/// retired <c>HotstringEmitter</c> Script branch produced for the same row, so generated scripts
/// are unchanged across the Script→Raw transition.
///
/// This is the single C# home of the transform, shared by history restore/revert
/// (<see cref="ToDefinition"/>) and the edit dialog's kind-switch compose. The EF data migration
/// hand-writes the same logic in T-SQL (SQL can't call C#); a Testcontainers parity test enforces
/// the two agree. Mirrors <c>HotstringEmitter.BuildOptions</c> (X/T never apply to a brace-body
/// kind) and <c>HotstringEmitter.Escape</c> on the trigger.
/// </summary>
internal static class ScriptToRawComposer
{
    /// <summary>Composes the verbatim <c>:options:trigger::</c> definition with a brace body.</summary>
    public static string Compose(
        string trigger,
        string replacement,
        bool isEndingCharacterRequired,
        bool isTriggerInsideWord,
        bool isCaseSensitive,
        bool omitEndingCharacter)
    {
        string options = "";
        if (!isEndingCharacterRequired) options += "*";
        if (isTriggerInsideWord) options += "?";
        if (isCaseSensitive) options += "C";
        if (omitEndingCharacter && isEndingCharacterRequired) options += "O"; // O is meaningless with *

        return $":{options}:{Escape(trigger)}::\n{{\n{replacement}\n}}";
    }

    /// <summary>
    /// Builds the <see cref="HotstringDefinition"/> to persist when restoring or reverting a
    /// snapshot. A legacy <c>Kind = Script</c> snapshot is converted to a Raw definition (composed
    /// verbatim, derived trigger unchanged); every other kind is applied as-is.
    /// </summary>
    public static HotstringDefinition ToDefinition(HotstringSnapshot s)
    {
#pragma warning disable CS0618 // Script is read only from stored legacy snapshots, never new payloads.
        bool isLegacyScript = s.Kind == HotstringKind.Script;
#pragma warning restore CS0618

        if (isLegacyScript)
        {
            string raw = Compose(
                s.Trigger, s.Replacement,
                s.IsEndingCharacterRequired, s.IsTriggerInsideWord,
                s.IsCaseSensitive, s.OmitEndingCharacter);

            return new HotstringDefinition(
                s.Trigger, raw, s.Description, s.AppliesToAllProfiles,
                s.IsEndingCharacterRequired, s.IsTriggerInsideWord,
                HotstringKind.Raw, s.IsCaseSensitive, s.OmitEndingCharacter,
                s.DateTimeFormat, s.DateOffsetAmount, s.DateOffsetUnit,
                s.ContextMatchType, s.ContextValue);
        }

        return new HotstringDefinition(
            s.Trigger, s.Replacement, s.Description, s.AppliesToAllProfiles,
            s.IsEndingCharacterRequired, s.IsTriggerInsideWord,
            s.Kind, s.IsCaseSensitive, s.OmitEndingCharacter,
            s.DateTimeFormat, s.DateOffsetAmount, s.DateOffsetUnit,
            s.ContextMatchType, s.ContextValue);
    }

    // Mirrors HotstringEmitter.Escape: backtick first so later escapes are not double-escaped.
    private static string Escape(string value) =>
        value
            .Replace("`", "``")
            .Replace("\n", "`n")
            .Replace("\r", "`r")
            .Replace("\t", "`t")
            .Replace(";", "`;");
}
