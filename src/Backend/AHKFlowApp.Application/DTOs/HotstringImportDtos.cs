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
