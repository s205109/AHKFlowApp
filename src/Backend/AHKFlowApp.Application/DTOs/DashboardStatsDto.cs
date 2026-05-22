namespace AHKFlowApp.Application.DTOs;

/// <summary>Aggregated stats for the home dashboard.</summary>
/// <param name="Hotstrings">Hotstring totals plus recent-creation buckets.</param>
/// <param name="Hotkeys">Hotkey totals plus recent-creation buckets.</param>
/// <param name="Profiles">Profile counts, including total, active, and default.</param>
/// <param name="RecentActivity">Recently created or updated entities, newest first.</param>
public sealed record DashboardStatsDto(
    EntityStatsDto Hotstrings,
    EntityStatsDto Hotkeys,
    ProfileStatsDto Profiles,
    IReadOnlyList<RecentActivityItemDto> RecentActivity);

/// <summary>Counts for an entity kind shown on the dashboard.</summary>
/// <param name="Total">Total number of entities owned by the user.</param>
/// <param name="CreatedThisWeek">Number created in the past 7 days.</param>
/// <param name="DailyBuckets">Per-day creation counts for the past 7 days, oldest first.</param>
public sealed record EntityStatsDto(
    int Total,
    int CreatedThisWeek,
    IReadOnlyList<int> DailyBuckets);

/// <summary>Profile-specific counts for the dashboard.</summary>
/// <param name="Total">Total profiles owned by the user.</param>
/// <param name="Active">Profiles containing at least one hotstring or hotkey.</param>
/// <param name="Default">Always 0 or 1; number of default profiles.</param>
/// <param name="DailyBuckets">Per-day creation counts for the past 7 days, oldest first.</param>
public sealed record ProfileStatsDto(
    int Total,
    int Active,
    int Default,
    IReadOnlyList<int> DailyBuckets);

/// <summary>A single line in the recent-activity stream.</summary>
/// <param name="Kind">Entity kind, such as <c>Hotstring</c>, <c>Hotkey</c>, or <c>Profile</c>.</param>
/// <param name="Action">Action verb, such as <c>Created</c> or <c>Updated</c>.</param>
/// <param name="Label">Human-readable label, such as a trigger, description, or profile name.</param>
/// <param name="OccurredAt">UTC timestamp when the action happened.</param>
public sealed record RecentActivityItemDto(
    string Kind,
    string Action,
    string Label,
    DateTimeOffset OccurredAt);
