using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Dashboard;

public sealed record GetDashboardStatsQuery : IRequest<Result<DashboardStatsDto>>;

internal sealed class GetDashboardStatsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<GetDashboardStatsQuery, Result<DashboardStatsDto>>
{
    private const int BucketDays = 14;
    private const int RecentActivityCount = 5;

    public async Task<Result<DashboardStatsDto>> Handle(GetDashboardStatsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        DateTimeOffset now = clock.GetUtcNow();
        DateTimeOffset weekAgo = now.AddDays(-7);
        DateTimeOffset bucketStart = new DateTimeOffset(now.UtcDateTime.Date, TimeSpan.Zero).AddDays(-(BucketDays - 1));

        int hotstringsTotal = await db.Hotstrings.CountAsync(h => h.OwnerOid == ownerOid, ct);
        int hotstringsThisWeek = await db.Hotstrings.CountAsync(h => h.OwnerOid == ownerOid && h.CreatedAt >= weekAgo, ct);
        IReadOnlyList<int> hotstringBuckets = await BuildBucketsAsync(
            db.Hotstrings.Where(h => h.OwnerOid == ownerOid).Select(h => h.CreatedAt),
            bucketStart, ct);
        var hotstrings = new EntityStatsDto(hotstringsTotal, hotstringsThisWeek, hotstringBuckets);

        int hotkeysTotal = await db.Hotkeys.CountAsync(h => h.OwnerOid == ownerOid, ct);
        int hotkeysThisWeek = await db.Hotkeys.CountAsync(h => h.OwnerOid == ownerOid && h.CreatedAt >= weekAgo, ct);
        IReadOnlyList<int> hotkeyBuckets = await BuildBucketsAsync(
            db.Hotkeys.Where(h => h.OwnerOid == ownerOid).Select(h => h.CreatedAt),
            bucketStart, ct);
        var hotkeys = new EntityStatsDto(hotkeysTotal, hotkeysThisWeek, hotkeyBuckets);

        int profilesTotal = await db.Profiles.CountAsync(p => p.OwnerOid == ownerOid, ct);
        int profilesDefault = await db.Profiles.CountAsync(p => p.OwnerOid == ownerOid && p.IsDefault, ct);
        IReadOnlyList<int> profileBuckets = await BuildBucketsAsync(
            db.Profiles.Where(p => p.OwnerOid == ownerOid).Select(p => p.CreatedAt),
            bucketStart, ct);
        var profiles = new ProfileStatsDto(profilesTotal, profilesTotal - profilesDefault, profilesDefault, profileBuckets);

        IReadOnlyList<RecentActivityItemDto> recent = await BuildRecentActivityAsync(ownerOid, ct);

        return Result.Success(new DashboardStatsDto(hotstrings, hotkeys, profiles, recent));
    }

    private static async Task<IReadOnlyList<int>> BuildBucketsAsync(
        IQueryable<DateTimeOffset> datesQuery,
        DateTimeOffset bucketStart,
        CancellationToken ct)
    {
        List<DateTimeOffset> dates = await datesQuery
            .Where(d => d >= bucketStart)
            .ToListAsync(ct);

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
        List<RecentActivityItemDto> hsItems = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt)
            .Take(RecentActivityCount)
            .Select(h => new RecentActivityItemDto(
                "hotstring",
                h.UpdatedAt > h.CreatedAt ? "updated" : "created",
                h.Trigger,
                h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt))
            .ToListAsync(ct);

        List<RecentActivityItemDto> hkItems = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt)
            .Take(RecentActivityCount)
            .Select(h => new RecentActivityItemDto(
                "hotkey",
                h.UpdatedAt > h.CreatedAt ? "updated" : "created",
                h.Description,
                h.UpdatedAt > h.CreatedAt ? h.UpdatedAt : h.CreatedAt))
            .ToListAsync(ct);

        List<RecentActivityItemDto> pItems = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid)
            .OrderByDescending(p => p.UpdatedAt > p.CreatedAt ? p.UpdatedAt : p.CreatedAt)
            .Take(RecentActivityCount)
            .Select(p => new RecentActivityItemDto(
                "profile",
                p.UpdatedAt > p.CreatedAt ? "updated" : "created",
                p.Name,
                p.UpdatedAt > p.CreatedAt ? p.UpdatedAt : p.CreatedAt))
            .ToListAsync(ct);

        return hsItems.Concat(hkItems).Concat(pItems)
            .OrderByDescending(x => x.OccurredAt)
            .Take(RecentActivityCount)
            .ToList();
    }
}
