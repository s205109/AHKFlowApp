namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record HotkeyListRequest(
    Guid? ProfileId = null,
    string? Search = null,
    int Page = 1,
    int PageSize = 50,
    string? SortField = null,
    bool SortDescending = true,
    string? DescriptionFilter = null,
    string? KeyFilter = null,
    HotkeyActionKind? ActionKind = null,
    bool? AppliesToAllProfiles = null,
    bool? Ctrl = null,
    bool? Alt = null,
    bool? Shift = null,
    bool? Win = null,
    IReadOnlyList<Guid>? CategoryIds = null);
