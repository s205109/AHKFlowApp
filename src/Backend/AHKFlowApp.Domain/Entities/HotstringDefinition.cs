using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Domain.Entities;

/// <summary>
/// Definitional fields of a hotstring, grouped so factory signatures stay stable
/// as kinds and options grow across the redesign phases.
/// </summary>
public sealed record HotstringDefinition(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);
