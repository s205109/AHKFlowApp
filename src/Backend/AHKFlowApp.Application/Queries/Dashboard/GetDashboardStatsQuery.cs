using AHKFlowApp.Application.Abstractions;
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

        DateTimeOffset now = clock.GetUtcNow();
        DateTimeOffset weekAgo = now.AddDays(-7);
        DateTimeOffset bucketStart = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero).AddDays(-(BucketDays - 1));

        int hotstringsTotal = await db.Hotstrings.CountAsync(h => h.OwnerOid == ownerOid, ct);
        int hotstringsThisWeek = await db.Hotstrings.CountAsync(h => h.OwnerOid == ownerOid && h.CreatedAt >= weekAgo, ct);
        List<DateTimeOffset> hotstringWindow = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid && h.CreatedAt >= bucketStart)
            .Select(h => h.CreatedAt)
            .ToListAsync(ct);
        var hotstrings = new EntityStatsDto(hotstringsTotal, hotstringsThisWeek, BuildBuckets(hotstringWindow, bucketStart));

        int hotkeysTotal = await db.Hotkeys.CountAsync(h => h.OwnerOid == ownerOid, ct);
        int hotkeysThisWeek = await db.Hotkeys.CountAsync(h => h.OwnerOid == ownerOid && h.CreatedAt >= weekAgo, ct);
        List<DateTimeOffset> hotkeyWindow = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid && h.CreatedAt >= bucketStart)
            .Select(h => h.CreatedAt)
            .ToListAsync(ct);
        var hotkeys = new EntityStatsDto(hotkeysTotal, hotkeysThisWeek, BuildBuckets(hotkeyWindow, bucketStart));

        int profilesTotal = await db.Profiles.CountAsync(p => p.OwnerOid == ownerOid, ct);
        int profilesDefault = await db.Profiles.CountAsync(p => p.OwnerOid == ownerOid && p.IsDefault, ct);
        List<DateTimeOffset> profileWindow = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid && p.CreatedAt >= bucketStart)
            .Select(p => p.CreatedAt)
            .ToListAsync(ct);
        var profiles = new ProfileStatsDto(profilesTotal, profilesTotal - profilesDefault, profilesDefault, BuildBuckets(profileWindow, bucketStart));

        IReadOnlyList<RecentActivityItemDto> recent = await BuildRecentActivityAsync(ownerOid, ct);

        return Result.Success(new DashboardStatsDto(hotstrings, hotkeys, profiles, recent));
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
