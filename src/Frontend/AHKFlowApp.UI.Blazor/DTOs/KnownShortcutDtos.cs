namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>One thing that uses a known shortcut. Client copy of the API DTO.</summary>
public sealed record ShortcutUseDto(
    string UsedBy,
    ShortcutProtection Protection,
    ShortcutScope Scope,
    string Does);

/// <summary>One key-and-modifier combination something outside AHKFlow uses.</summary>
public sealed record KnownShortcutDto(
    string Id,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    IReadOnlyList<ShortcutUseDto> Uses,
    string? WarningText);

/// <summary>The whole known-shortcut list the dialog matches against.</summary>
public sealed record KnownShortcutCatalogDto(IReadOnlyList<KnownShortcutDto> Shortcuts);

/// <summary>Where a known-shortcut record came from. Client copy of the API enum.</summary>
public enum ShortcutRecordOrigin
{
    /// <summary>Shipped in the curated manifest.</summary>
    BuiltIn = 0,

    /// <summary>Recorded by the owner.</summary>
    Owner = 1,
}

/// <summary>One use as the management page needs it, with the state that page can change.</summary>
public sealed record ManagedShortcutUseDto(
    string UsedBy,
    ShortcutProtection Protection,
    ShortcutScope Scope,
    string Does,
    ShortcutRecordOrigin Origin,
    Guid? OwnerRecordId,
    bool IsIgnored);

/// <summary>One combination and every use of it, ignored ones included so they can be restored.</summary>
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
