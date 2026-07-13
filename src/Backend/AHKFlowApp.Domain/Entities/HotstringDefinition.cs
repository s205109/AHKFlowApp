using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotstring, grouped so factory signatures stay stable
/// as kinds and options grow across the redesign phases.
/// </summary>
/// <param name="Replacement">
/// Meaning is kind-dependent. For <see cref="HotstringKind.Text"/> it is the literal
/// replacement text; for <see cref="HotstringKind.Macro"/> the macro token string; for
/// <see cref="HotstringKind.Raw"/> the <em>entire verbatim AHK v2 definition</em>
/// (first line <c>:options:trigger::</c>, optional brace body below) — the single source
/// of truth from which <c>Trigger</c> and option flags are derived server-side.
/// </param>
public sealed record HotstringDefinition(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null);
