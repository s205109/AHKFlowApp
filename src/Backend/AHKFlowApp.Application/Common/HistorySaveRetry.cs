using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Common;

internal static class HistorySaveRetry
{
    private const string HistoryVersionIndexName = "IX_EntityHistory_Owner_Type_Entity_Version";

    internal static bool IsHistoryVersionConflict(this DbUpdateException ex) =>
        ex.IsDuplicateKeyViolation()
        && ex.InnerException?.Message.Contains(HistoryVersionIndexName, StringComparison.Ordinal) == true;

    internal static Task SaveWithHistoryRetryAsync(
        this IAppDbContext db, EntityHistory entry, CancellationToken ct) =>
        db.SaveWithHistoryRetryAsync([entry], ct);

    internal static async Task SaveWithHistoryRetryAsync(
        this IAppDbContext db, IReadOnlyList<EntityHistory> entries, CancellationToken ct)
    {
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsHistoryVersionConflict())
        {
            foreach (EntityHistory entry in entries)
            {
                int max = await db.EntityHistories
                    .Where(h => h.EntityType == entry.EntityType && h.EntityId == entry.EntityId)
                    .MaxAsync(h => (int?)h.Version, ct) ?? 0;
                if (max >= entry.Version)
                    entry.ReassignVersion(max + 1);
            }

            await db.SaveChangesAsync(ct);
        }
    }
}
