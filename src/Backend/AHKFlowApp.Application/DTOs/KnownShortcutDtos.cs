using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>One thing that uses a known shortcut, as the dialog needs it.</summary>
/// <param name="UsedBy">Windows, a named application, or a label the owner typed.</param>
/// <param name="Protection">How hard the keys are to take over.</param>
/// <param name="Scope">Whether the use fires anywhere, or only while its application is in front.</param>
/// <param name="Does">Lowercase verb phrase the warning composer completes a sentence with.</param>
public sealed record ShortcutUseDto(
    string UsedBy,
    ShortcutProtection Protection,
    ShortcutScope Scope,
    string Does);

/// <summary>
/// One key-and-modifier combination something outside AHKFlow uses, with every use of it.
/// EvidenceUrl and EvidenceCheckedOn stay server-side: they justify curation, and the dialog
/// never shows them.
/// </summary>
/// <param name="Id">Stable identifier for the row, such as "windows.file-explorer".</param>
/// <param name="Key">Canonical key spelling. Letter keys are lowercase.</param>
/// <param name="Ctrl">True when the combination needs Ctrl.</param>
/// <param name="Alt">True when the combination needs Alt.</param>
/// <param name="Shift">True when the combination needs Shift.</param>
/// <param name="Win">True when the combination needs the Windows key.</param>
/// <param name="Uses">Everything that uses this combination. At least one.</param>
/// <param name="WarningText">Hand-written warning text for this row, or null to compose it.</param>
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
/// <param name="Shortcuts">Every curated combination, one record each.</param>
public sealed record KnownShortcutCatalogDto(IReadOnlyList<KnownShortcutDto> Shortcuts);
