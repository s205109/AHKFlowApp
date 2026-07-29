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
