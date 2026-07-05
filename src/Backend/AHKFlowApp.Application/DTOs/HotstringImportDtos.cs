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
public sealed record HotstringImportPreviewDto(
    HotstringImportRowDto[] Rows,
    int ReadyCount,
    int WarningCount,
    int DuplicateCount,
    int InvalidCount);

/// <summary>Request body for the preview endpoint.</summary>
public sealed record PreviewHotstringImportRequestDto(string Script);

/// <summary>Request body for the commit endpoint: raw script + one profile target for the batch.</summary>
public sealed record ImportHotstringsRequestDto(
    string Script,
    bool AppliesToAllProfiles = true,
    Guid[]? ProfileIds = null);

/// <summary>Commit outcome. Rows carries every processed line with its final status.</summary>
public sealed record HotstringImportResultDto(
    int ImportedCount,
    int WarningCount,
    HotstringImportRowDto[] Rows);
