namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record DashboardStatsDto(
    EntityStatsDto Hotstrings,
    EntityStatsDto Hotkeys,
    ProfileStatsDto Profiles,
    IReadOnlyList<RecentActivityItemDto> RecentActivity);

public sealed record EntityStatsDto(
    int Total,
    int CreatedThisWeek,
    IReadOnlyList<int> DailyBuckets);

public sealed record ProfileStatsDto(
    int Total,
    int Active,
    int Default,
    IReadOnlyList<int> DailyBuckets);

public sealed record RecentActivityItemDto(
    string Kind,
    string Action,
    string Label,
    DateTimeOffset OccurredAt);
