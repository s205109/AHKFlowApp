namespace AHKFlowApp.UI.Blazor.DTOs;

public enum HotstringImportRowStatus
{
    Ready,
    Warning,
    Duplicate,
    Invalid,
}

public sealed record HotstringImportRowDto(
    int LineNumber,
    string Trigger,
    string Replacement,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string[] IgnoredFlags,
    HotstringImportRowStatus Status,
    string? Reason);

public sealed record HotstringImportPreviewDto(
    HotstringImportRowDto[] Rows,
    int ReadyCount,
    int WarningCount,
    int DuplicateCount,
    int InvalidCount);

public sealed record ImportHotstringsRequestDto(
    string Script,
    bool AppliesToAllProfiles = true,
    Guid[]? ProfileIds = null);

public sealed record HotstringImportResultDto(
    int ImportedCount,
    int WarningCount,
    HotstringImportRowDto[] Rows);
