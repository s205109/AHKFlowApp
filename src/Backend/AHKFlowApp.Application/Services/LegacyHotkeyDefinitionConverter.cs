using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Converts a legacy hotkey (two-value <see cref="HotkeyAction"/> + free <c>Parameters</c>) into the
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
/// </remarks>
public static class LegacyHotkeyDefinitionConverter
{
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

    /// <summary>Returns <paramref name="legacy"/> with its typed fields filled from its legacy pair.</summary>
    public static HotkeyDefinition Apply(HotkeyDefinition legacy)
    {
        TypedAction t = ToTyped(legacy.Action, legacy.Parameters);
        return legacy with
        {
            ActionKind = t.ActionKind,
            Text = t.Text,
            SendKeysContent = t.SendKeysContent,
            RunTarget = t.RunTarget,
            RunTargetKind = t.RunTargetKind,
            WindowOp = t.WindowOp,
            RemapDest = t.RemapDest,
            Body = t.Body,
        };
    }

    private static RunTargetKind RunTargetKindFor(string parameters) =>
        parameters.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
        || parameters.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            ? Domain.Enums.RunTargetKind.Url
            : Domain.Enums.RunTargetKind.Application;
}
