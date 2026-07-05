namespace AHKFlowApp.Application.DTOs;

/// <summary>Outcome of a single parsed/classified import line.</summary>
public enum HotstringImportRowStatus
{
    /// <summary>Parsed cleanly; will import.</summary>
    Ready,

    /// <summary>Imports, but one or more unsupported option flags were dropped.</summary>
    Warning,

    /// <summary>Trigger already exists (for the owner or earlier in the file); skipped.</summary>
    Duplicate,

    /// <summary>Failed syntax/validation; skipped.</summary>
    Invalid,
}

/// <summary>One parsed line of an imported script.</summary>
/// <param name="LineNumber">1-based line number in the source script.</param>
/// <param name="Trigger">Parsed trigger, trimmed of surrounding whitespace.</param>
/// <param name="Replacement">Parsed replacement text, kept verbatim.</param>
/// <param name="IsEndingCharacterRequired">Whether an ending character is required to expand (false when the <c>*</c> flag is present).</param>
/// <param name="IsTriggerInsideWord">Whether the trigger fires inside a word (true when the <c>?</c> flag is present).</param>
/// <param name="IgnoredFlags">Unsupported option flags that were dropped, preserved as their exact tokens.</param>
/// <param name="Status">Classification outcome for this line.</param>
/// <param name="Reason">Human-readable reason when the line is Warning, Duplicate, or Invalid; otherwise null.</param>
public sealed record HotstringImportRowDto(
    int LineNumber,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string[] IgnoredFlags,
    HotstringImportRowStatus Status,
    string? Reason);

/// <summary>Read-only preview of a parsed script, with per-status counts.</summary>
/// <param name="Rows">Every parsed line with its classification, in source order.</param>
/// <param name="ReadyCount">Number of rows that will import cleanly.</param>
/// <param name="WarningCount">Number of rows that will import despite dropped flags.</param>
/// <param name="DuplicateCount">Number of rows skipped as duplicates.</param>
/// <param name="InvalidCount">Number of rows skipped as invalid.</param>
public sealed record HotstringImportPreviewDto(
    HotstringImportRowDto[] Rows,
    int ReadyCount,
    int WarningCount,
    int DuplicateCount,
    int InvalidCount);

/// <summary>Request body for the preview endpoint.</summary>
/// <param name="Script">Raw AutoHotkey script text to parse.</param>
public sealed record PreviewHotstringImportRequestDto(string Script);

/// <summary>Request body for the commit endpoint: raw script + one profile target for the batch.</summary>
/// <param name="Script">Raw AutoHotkey script text to parse and import.</param>
/// <param name="AppliesToAllProfiles">When true, imported hotstrings apply to all profiles; when false, only to <paramref name="ProfileIds"/>.</param>
/// <param name="ProfileIds">Target profile ids when <paramref name="AppliesToAllProfiles"/> is false.</param>
public sealed record ImportHotstringsRequestDto(
    string Script,
    bool AppliesToAllProfiles = true,
    Guid[]? ProfileIds = null);

/// <summary>Commit outcome. Rows carries every processed line with its final status.</summary>
/// <param name="ImportedCount">Number of hotstrings actually created.</param>
/// <param name="WarningCount">Number of imported hotstrings that had dropped flags.</param>
/// <param name="Rows">Every processed line with its final status.</param>
public sealed record HotstringImportResultDto(
    int ImportedCount,
    int WarningCount,
    HotstringImportRowDto[] Rows);
