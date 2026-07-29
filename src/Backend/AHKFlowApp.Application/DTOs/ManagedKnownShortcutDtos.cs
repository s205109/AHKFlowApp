using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>One use as the management page needs it, with the state that page can change.</summary>
/// <param name="UsedBy">Windows, a named application, or a label the owner typed.</param>
/// <param name="Protection">How hard the keys are to take over.</param>
/// <param name="Scope">Whether the use fires anywhere, or only while its application is in front.</param>
/// <param name="Does">Lowercase verb phrase the warning composer completes a sentence with.</param>
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
/// <param name="Id">Built-in id such as "windows.file-explorer", or "owner.&lt;guid&gt;" for an owner-only combination.</param>
/// <param name="Key">Canonical key spelling. Letter keys are lowercase.</param>
/// <param name="Ctrl">True when the combination needs Ctrl.</param>
/// <param name="Alt">True when the combination needs Alt.</param>
/// <param name="Shift">True when the combination needs Shift.</param>
/// <param name="Win">True when the combination needs the Windows key.</param>
/// <param name="Uses">Every use of this combination, ignored ones included.</param>
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
/// <param name="Shortcuts">Every combination, built-in and owner-recorded alike.</param>
public sealed record ManagedKnownShortcutCatalogDto(IReadOnlyList<ManagedKnownShortcutDto> Shortcuts);

/// <summary>An owner's new record of something that uses a combination.</summary>
/// <param name="Key">Key name. The handler canonicalizes it before saving.</param>
/// <param name="Ctrl">True when the combination needs Ctrl.</param>
/// <param name="Alt">True when the combination needs Alt.</param>
/// <param name="Shift">True when the combination needs Shift.</param>
/// <param name="Win">True when the combination needs the Windows key.</param>
/// <param name="UsedBy">What uses the keys — a product name, or any label the owner types.</param>
/// <param name="Scope">Whether the use fires anywhere, or only while its application is in front.</param>
/// <param name="Does">Lowercase verb phrase completing "&lt;UsedBy&gt; uses &lt;combo&gt; to …".</param>
/// <param name="Protection">Normal or Unknown. An owner cannot claim Protected.</param>
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
/// <param name="ShortcutId">Built-in id, for example "windows.file-explorer".</param>
/// <param name="UsedBy">Which use of that shortcut, for example "Windows" or "Chrome".</param>
public sealed record KnownShortcutUseRefDto(string ShortcutId, string UsedBy);
