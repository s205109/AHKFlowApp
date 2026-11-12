using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

internal static class ProfileDefaults
{
    internal const string ChangedAtTheSameTime = "Another profile became the default at the same time. Try again.";

    // Clears the owner's other defaults in a save of its own, so the unique default index
    // never sees two defaults. The caller sets the new default in a second save.
    internal static async Task ClearOthersAsync(
        IAppDbContext db, Guid ownerOid, Guid newDefaultId, TimeProvider clock, CancellationToken ct)
    {
        List<Profile> others = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid && p.IsDefault && p.Id != newDefaultId)
            .ToListAsync(ct);
        if (others.Count == 0)
            return;

        foreach (Profile other in others)
            other.MarkDefault(false, clock);

        await db.SaveChangesAsync(ct);
    }
}
