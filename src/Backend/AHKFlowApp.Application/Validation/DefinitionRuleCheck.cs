using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation.Results;

namespace AHKFlowApp.Application.Validation;

/// <summary>
/// Runs the rules a new save must pass over a definition that came out of a stored Snapshot.
/// The four history handlers call this; nothing else should need it.
/// <para>
/// Static, like <c>ScriptToRawComposer</c> and <c>LegacyHotkeySnapshotConverter</c> beside it in
/// the same call. It is a pure function with no dependency to inject — no database, no clock, no
/// I/O — and injecting it would add a constructor parameter to four handlers that tests build by
/// hand in 18 places, including the legacy restore tests backlog 162 must leave untouched.
/// </para>
/// </summary>
internal static class DefinitionRuleCheck
{
    // Built once. A FluentValidation validator holds only rule definitions and is safe to reuse,
    // which is why AddValidatorsFromAssembly can register them as singletons.
    private static readonly HotstringDefinitionValidator s_hotstring = new();
    private static readonly HotkeyDefinitionValidator s_hotkey = new();

    /// <summary>Returns one error per failed rule, or an empty array when the definition passes.</summary>
    public static ValidationError[] Check(HotstringDefinition definition) =>
        ToErrors(s_hotstring.Validate(definition));

    /// <summary>
    /// Returns one error per failed rule, or an empty array when the definition passes. The
    /// caller passes the definition the legacy converter produced, not the stored Snapshot
    /// shape: the converted definition is what the Emitter will read.
    /// </summary>
    public static ValidationError[] Check(HotkeyDefinition definition) =>
        ToErrors(s_hotkey.Validate(new HotkeyDefinitionDraft(definition)));

    private static ValidationError[] ToErrors(ValidationResult result) =>
        [.. result.Errors.Select(failure => new ValidationError
        {
            Identifier = failure.PropertyName,
            ErrorMessage = failure.ErrorMessage,
        })];
}
