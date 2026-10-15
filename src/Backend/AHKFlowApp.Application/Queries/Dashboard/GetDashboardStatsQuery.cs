using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Dashboard;

public sealed record GetDashboardStatsQuery;

internal sealed class GetDashboardStatsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<GetDashboardStatsQuery, Result<DashboardStatsDto>>
{
    private const int BucketDays = 14;
    private const int RecentActivityCount = 5;

    private const string KindHotstring = "hotstring";
    private const string KindHotkey = "hotkey";
    private const string KindProfile = "profile";
    private const string ActionCreated = "created";
    private const string ActionUpdated = "updated";

    public async Task<Result<DashboardStatsDto>> ExecuteAsync(GetDashboardStatsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        // Count the profile the app guarantees, even before the owner opens the profiles page.
        await db.EnsureDefaultProfileAsync(ownerOid, clock, ct);

        DateTimeOffset now = clock.GetUtcNow();
        DateTimeOffset weekAgo = now.AddDays(-7);
        DateTimeOffset bucketStart = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero).AddDays(-(BucketDays - 1));

        EntityStatsDto hotstrings = await BuildStatsAsync(
            db.Hotstrings.Where(h => h.OwnerOid == ownerOid).Select(h => h.CreatedAt), weekAgo, bucketStart, ct);
        EntityStatsDto hotkeys = await BuildStatsAsync(
            db.Hotkeys.Where(h => h.OwnerOid == ownerOid).Select(h => h.CreatedAt), weekAgo, bucketStart, ct);
        EntityStatsDto profiles = await BuildStatsAsync(
            db.Profiles.Where(p => p.OwnerOid == ownerOid).Select(p => p.CreatedAt), weekAgo, bucketStart, ct);

        IReadOnlyList<RecentActivityItemDto> recent = await BuildRecentActivityAsync(ownerOid, ct);

        return Result.Success(new DashboardStatsDto(hotstrings, hotkeys, profiles, recent));
    }

    // The bucket window starts 13 days back, so it already holds every row from the past week.
    private static async Task<EntityStatsDto> BuildStatsAsync(
        IQueryable<DateTimeOffset> createdAt, DateTimeOffset weekAgo, DateTimeOffset bucketStart, CancellationToken ct)
    {
        int total = await createdAt.CountAsync(ct);
        List<DateTimeOffset> window = await createdAt.Where(d => d >= bucketStart).ToListAsync(ct);
        return new EntityStatsDto(total, window.Count(d => d >= weekAgo), BuildBuckets(window, bucketStart));
    }

    private static IReadOnlyList<int> BuildBuckets(IEnumerable<DateTimeOffset> dates, DateTimeOffset bucketStart)
    {
        int[] buckets = new int[BucketDays];
        DateTime startDate = bucketStart.UtcDateTime.Date;
        foreach (DateTimeOffset d in dates)
        {
            int idx = (int)(d.UtcDateTime.Date - startDate).TotalDays;
            if (idx >= 0 && idx < BucketDays)
                buckets[idx]++;
        }
        return buckets;
    }

    private async Task<IReadOnlyList<RecentActivityItemDto>> BuildRecentActivityAsync(Guid ownerOid, CancellationToken ct)
    {
        // OccurredAt and Action computed inline — EF Core cannot reuse projected column aliases in ORDER BY
        List<RecentActivityItemDto> hsItems = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt)
            .Take(RecentActivityCount)
            .Select(h => new RecentActivityItemDto(
                KindHotstring,
                h.UpdatedAt > h.CreatedAt ? ActionUpdated : ActionCreated,
                h.Trigger,
                h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt))
            .ToListAsync(ct);

        // OccurredAt and Action computed inline — EF Core cannot reuse projected column aliases in ORDER BY
        List<RecentActivityItemDto> hkItems = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt)
            .Take(RecentActivityCount)
            .Select(h => new RecentActivityItemDto(
                KindHotkey,
                h.UpdatedAt > h.CreatedAt ? ActionUpdated : ActionCreated,
                h.Description,
                h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt))
            .ToListAsync(ct);

        // OccurredAt and Action computed inline — EF Core cannot reuse projected column aliases in ORDER BY
        List<RecentActivityItemDto> pItems = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid)
            .OrderByDescending(p => p.UpdatedAt > p.CreatedAt ? p.UpdatedAt : p.CreatedAt)
            .Take(RecentActivityCount)
            .Select(p => new RecentActivityItemDto(
                KindProfile,
                p.UpdatedAt > p.CreatedAt ? ActionUpdated : ActionCreated,
                p.Name,
                p.UpdatedAt > p.CreatedAt ? p.UpdatedAt : p.CreatedAt))
            .ToListAsync(ct);

        return hsItems.Concat(hkItems).Concat(pItems)
            .OrderByDescending(x => x.OccurredAt)
            .Take(RecentActivityCount)
            .ToList();
    }
}
