using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation.Results;

namespace AHKFlowApp.Application.Validation;

/// <summary>
/// Runs the rules a new save must pass over a definition that came out of a stored Snapshot.
/// The four history handlers and the item reads call this.
/// <para>
/// Static, like <c>ScriptToRawComposer</c> and <c>LegacyHotkeySnapshotConverter</c> beside it in
/// the same call. It is a pure function with nothing to inject: no database, no clock, no I/O.
/// </para>
/// </summary>
internal static class DefinitionRuleCheck
{
    // One instance each, reused across calls. A FluentValidation validator holds only rule
    // definitions after construction, and per-call state lives on ValidationContext, so sharing
    // one instance between concurrent calls is safe.
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

    /// <summary>
    /// Checks a stored hotstring and returns its broken rules, or null when it breaks none. The
    /// caller decides whether the item applies to no profile.
    /// </summary>
    public static IReadOnlyList<BrokenRuleDto>? BrokenRules(Hotstring stored) =>
        ToBrokenRules(Check(stored.ToDefinition()));

    /// <summary>
    /// Checks a stored hotkey and returns its broken rules, or null when it breaks none. The
    /// caller decides whether the item applies to no profile.
    /// </summary>
    public static IReadOnlyList<BrokenRuleDto>? BrokenRules(Hotkey stored) =>
        ToBrokenRules(Check(stored.ToDefinition()));

    /// <summary>
    /// Turns the errors into the wire shape. Returns null for an empty array, because the API
    /// never sends an empty list of broken rules.
    /// </summary>
    public static IReadOnlyList<BrokenRuleDto>? ToBrokenRules(ValidationError[] errors) =>
        errors.Length == 0
            ? null
            : [.. errors.Select(e => new BrokenRuleDto(e.Identifier, e.ErrorMessage))];

    private static ValidationError[] ToErrors(ValidationResult result) =>
        [.. result.Errors.Select(failure => new ValidationError
        {
            Identifier = failure.PropertyName,
            ErrorMessage = failure.ErrorMessage,
        })];
}
