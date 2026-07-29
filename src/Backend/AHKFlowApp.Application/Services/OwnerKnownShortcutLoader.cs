using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Reads the two owner-scoped tables the merge needs. Three call sites want the same pair — the
/// dialog query, the management query, and the create command's reload — so the read lives here
/// and each of them cannot drift into a different owner filter.
/// </summary>
internal static class OwnerKnownShortcutLoader
{
    internal static async Task<(CustomKnownShortcut[] Owned, IgnoredKnownShortcut[] Ignored)> LoadAsync(
        IAppDbContext db, Guid ownerOid, CancellationToken ct)
    {
        CustomKnownShortcut[] owned = await db.CustomKnownShortcuts
            .Where(s => s.OwnerOid == ownerOid).AsNoTracking().ToArrayAsync(ct);

        IgnoredKnownShortcut[] ignored = await db.IgnoredKnownShortcuts
            .Where(i => i.OwnerOid == ownerOid).AsNoTracking().ToArrayAsync(ct);

        return (owned, ignored);
    }
}
