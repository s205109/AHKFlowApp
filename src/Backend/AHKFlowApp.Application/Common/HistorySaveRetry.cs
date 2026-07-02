using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Common;

internal static class HistorySaveRetry
{
    private const int MaxSaveAttempts = 5;

    internal static bool IsHistoryVersionConflict(this DbUpdateException ex) =>
        ex.IsDuplicateKeyViolation()
        && ex.InnerException?.Message.Contains(EntityHistoryIndexNames.OwnerTypeEntityVersion, StringComparison.Ordinal) == true;

    internal static Task SaveWithHistoryRetryAsync(
        this IAppDbContext db, EntityHistory entry, CancellationToken ct) =>
        db.SaveWithHistoryRetryAsync([entry], ct);

    internal static async Task SaveWithHistoryRetryAsync(
        this IAppDbContext db, IReadOnlyList<EntityHistory> entries, CancellationToken ct)
    {
        for (int attempt = 1; attempt <= MaxSaveAttempts; attempt++)
        {
            try
            {
                await db.SaveChangesAsync(ct);
                return;
            }
            catch (DbUpdateException ex) when (ex.IsHistoryVersionConflict() && attempt < MaxSaveAttempts)
            {
                await ReassignVersionsAsync(db, entries, ct);
            }
        }
    }

    private static async Task ReassignVersionsAsync(
        IAppDbContext db,
        IReadOnlyList<EntityHistory> entries,
        CancellationToken ct)
    {
        Guid[] ownerOids = [.. entries.Select(e => e.OwnerOid).Distinct()];
        TrackedEntityType[] entityTypes = [.. entries.Select(e => e.EntityType).Distinct()];
        Guid[] entityIds = [.. entries.Select(e => e.EntityId).Distinct()];

        var summaries = await db.EntityHistories
            .Where(h => ownerOids.Contains(h.OwnerOid)
                && entityTypes.Contains(h.EntityType)
                && entityIds.Contains(h.EntityId))
            .GroupBy(h => new { h.OwnerOid, h.EntityType, h.EntityId })
            .Select(g => new
            {
                g.Key.OwnerOid,
                g.Key.EntityType,
                g.Key.EntityId,
                MaxVersion = g.Max(h => h.Version),
            })
            .ToListAsync(ct);

        var nextVersionByEntity = summaries.ToDictionary(
            x => (x.OwnerOid, x.EntityType, x.EntityId),
            x => x.MaxVersion + 1);

        foreach (EntityHistory entry in entries)
        {
            (Guid OwnerOid, TrackedEntityType EntityType, Guid EntityId) key =
                (entry.OwnerOid, entry.EntityType, entry.EntityId);
            int nextVersion = nextVersionByEntity.TryGetValue(key, out int value)
                ? Math.Max(value, entry.Version)
                : entry.Version;

            if (nextVersion != entry.Version)
                entry.ReassignVersion(nextVersion);

            nextVersionByEntity[key] = nextVersion + 1;
        }
    }
}
