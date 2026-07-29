using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>One use as the management page needs it, with the state that page can change.</summary>
/// <param name="UsedBy"></param>
/// <param name="Protection"></param>
/// <param name="Scope"></param>
/// <param name="Does"></param>
/// <param name="Origin">BuiltIn or Owner. Decides which action the row offers.</param>
/// <param name="OwnerRecordId">Set for an Owner use, so the page can delete it. Null for BuiltIn.</param>
/// <param name="IsIgnored">True when the owner has silenced this BuiltIn use. Always false for Owner uses.</param>
public sealed record ManagedShortcutUseDto(
    string UsedBy,
    ShortcutProtection Protection,
    ShortcutScope Scope,
    string Does,
    ShortcutRecordOrigin Origin,
    Guid? OwnerRecordId,
    bool IsIgnored);

/// <summary>One combination and every use of it, ignored ones included so they can be restored.</summary>
/// <param name="Id"></param>
/// <param name="Key"></param>
/// <param name="Ctrl"></param>
/// <param name="Alt"></param>
/// <param name="Shift"></param>
/// <param name="Win"></param>
/// <param name="Uses"></param>
/// <param name="WarningText">
/// The built-in override text, carried straight through from the catalog. Null for an owner-only
/// combination, which has no built-in row to take it from. It rides along so the dialog list can
/// keep it — see <c>KnownShortcutMerge.ForDialog</c>.
/// </param>
public sealed record ManagedKnownShortcutDto(
    string Id,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    IReadOnlyList<ManagedShortcutUseDto> Uses,
    string? WarningText);

/// <summary>The whole management list.</summary>
public sealed record ManagedKnownShortcutCatalogDto(IReadOnlyList<ManagedKnownShortcutDto> Shortcuts);

/// <summary>An owner's new record of something that uses a combination.</summary>
public sealed record CreateCustomKnownShortcutDto(
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string UsedBy,
    ShortcutScope Scope,
    string Does,
    ShortcutProtection Protection = ShortcutProtection.Unknown);

/// <summary>Names one built-in use to silence or bring back.</summary>
public sealed record KnownShortcutUseRefDto(string ShortcutId, string UsedBy);
