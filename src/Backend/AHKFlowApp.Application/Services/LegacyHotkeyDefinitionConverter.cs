using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Converts a legacy hotkey (two-value <see cref="LegacyHotkeyDefinitionConverter.HotkeyAction"/> +
/// free <c>Parameters</c>) into the
/// typed W1 columns. The single C# home of the transform, shared by the write paths (expand phase)
/// and history restore/revert. The EF data migration hand-writes the same logic in T-SQL; a
/// Testcontainers parity test proves the two agree. Mirrors <c>ScriptToRawComposer</c>.
/// </summary>
/// <remarks>
/// Rules (spec §8): <c>Run</c> → <see cref="HotkeyActionKind.Run"/> with <c>RunTarget = Parameters</c>
/// and <c>RunTargetKind = Url</c> for an <c>http(s)://</c> prefix else <see cref="RunTargetKind.Application"/>;
/// <c>Send</c> that is a valid SendKeys token → <see cref="HotkeyActionKind.SendKeys"/>; every other
/// <c>Send</c> → <see cref="HotkeyActionKind.Raw"/> with a body reproducing the current escaped
/// emission byte-for-byte.
/// <para>
/// <b>Canonicalization exception.</b> Unlike the API write paths, this converter does <em>not</em>
/// fold a migrated <c>SendKeys</c> token onto its canonical spelling: legacy <c>Parameters</c> are
/// carried through verbatim. That is the byte-identity rule of spec §8 — a converted row must emit
/// exactly what it did before — and it keeps the hand-written T-SQL migration (which cannot run the
/// alias/width logic) in parity with this C# transform. The storage invariant therefore holds for
/// new API writes; legacy rows keep their original accepted spelling.
/// </para>
/// </remarks>
public static class LegacyHotkeyDefinitionConverter
{
    /// <summary>
    /// The retired two-value hotkey action. Kept solely as the legacy *input* type of this converter
    /// and of <see cref="AHKFlowApp.Application.DTOs.HotkeySnapshot.Action"/>; the entity and
    /// <see cref="HotkeyDefinition"/> dropped it in the Wave 1 contract phase, and the database
    /// columns went with Migration B. Numeric values must never change — pre-W1 history JSON in the
    /// database is deserialized through them.
    /// </summary>
    public enum HotkeyAction
    {
        /// <summary>Legacy send action: <c>Parameters</c> holds the key sequence or literal text.</summary>
        Send = 0,

        /// <summary>Legacy run action: <c>Parameters</c> holds the application path or URL.</summary>
        Run = 1,
    }

    /// <summary>The typed columns a legacy pair converts to.</summary>
    public readonly record struct TypedAction(
        HotkeyActionKind ActionKind,
        string? Text,
        string? SendKeysContent,
        string? RunTarget,
        RunTargetKind? RunTargetKind,
        WindowOp? WindowOp,
        string? RemapDest,
        string? Body);

    /// <summary>Converts a legacy (action, parameters) pair into the typed columns.</summary>
    public static TypedAction ToTyped(HotkeyAction action, string parameters) => action switch
    {
        HotkeyAction.Run => new TypedAction(
            HotkeyActionKind.Run, null, null, parameters, RunTargetKindFor(parameters), null, null, null),

        HotkeyAction.Send when HotkeyRules.Tokens.IsValidSendKeysContent(parameters) => new TypedAction(
            HotkeyActionKind.SendKeys, null, parameters, null, null, null, null, null),

        _ => new TypedAction(
            HotkeyActionKind.Raw, null, null, null, null, null, null,
            $"Send(\"{AhkEscaping.EscapeStringLiteral(parameters)}\")"),
    };

    /// <summary>
    /// Builds a typed <see cref="HotkeyDefinition"/> from a legacy (action, parameters) pair plus the
    /// fields that survived the contract phase unchanged.
    /// </summary>
    /// <param name="description">Human-readable label.</param>
    /// <param name="key">Main key.</param>
    /// <param name="ctrl">Ctrl modifier required.</param>
    /// <param name="alt">Alt modifier required.</param>
    /// <param name="shift">Shift modifier required.</param>
    /// <param name="win">Windows modifier required.</param>
    /// <param name="action">Legacy action discriminator.</param>
    /// <param name="parameters">Legacy action payload.</param>
    /// <param name="appliesToAllProfiles">When true, the hotkey applies to every profile.</param>
    public static HotkeyDefinition FromLegacy(
        string description,
        string key,
        bool ctrl,
        bool alt,
        bool shift,
        bool win,
        HotkeyAction action,
        string parameters,
        bool appliesToAllProfiles)
    {
        TypedAction t = ToTyped(action, parameters);
        return new HotkeyDefinition(
            Description: description,
            Key: key,
            Ctrl: ctrl,
            Alt: alt,
            Shift: shift,
            Win: win,
            ActionKind: t.ActionKind,
            AppliesToAllProfiles: appliesToAllProfiles,
            Text: t.Text,
            SendKeysContent: t.SendKeysContent,
            RunTarget: t.RunTarget,
            RunTargetKind: t.RunTargetKind,
            WindowOp: t.WindowOp,
            RemapDest: t.RemapDest,
            Body: t.Body);
    }

    private static RunTargetKind RunTargetKindFor(string parameters) =>
        parameters.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
        || parameters.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            ? Domain.Enums.RunTargetKind.Url
            : Domain.Enums.RunTargetKind.Application;
}
