using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Common;

internal static class DefaultProfileSeeding
{
    // An owner always has at least one profile. The first read that finds none creates the
    // Default profile, so every query that reports profiles sees the same rows.
    internal static async Task EnsureDefaultProfileAsync(
        this IAppDbContext db, Guid ownerOid, TimeProvider clock, CancellationToken ct)
    {
        if (await db.Profiles.AnyAsync(p => p.OwnerOid == ownerOid, ct))
            return;

        var seeded = Profile.Create(
            ownerOid,
            name: "Default",
            isDefault: true,
            headerTemplate: DefaultProfileTemplates.Header,
            footerTemplate: DefaultProfileTemplates.Footer,
            clock: clock);
        db.Profiles.Add(seeded);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // A concurrent first read already created the Default profile. Stop tracking this
            // copy, so a later save in the same request does not try to insert it again.
            db.Entry(seeded).State = EntityState.Detached;
        }
    }
}
