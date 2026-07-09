namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotstringListRequest(
    Guid? ProfileId = null,
    string? Search = null,
    int Page = 1,
    int PageSize = 50,
    string? SortField = null,
    bool SortDescending = true,
    string? TriggerFilter = null,
    string? ReplacementFilter = null,
    string? DescriptionFilter = null,
    bool? AppliesToAllProfiles = null,
    bool? IsEndingCharacterRequired = null,
    bool? IsTriggerInsideWord = null,
    IReadOnlyList<Guid>? CategoryIds = null,
    HotstringKind? Kind = null);
