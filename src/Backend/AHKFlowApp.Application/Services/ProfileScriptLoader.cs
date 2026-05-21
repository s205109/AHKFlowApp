using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Services;

public sealed class ProfileScriptLoader(IAppDbContext db)
{
    public sealed record LoadedProfile(
        Profile Profile,
        List<Hotstring> Hotstrings,
        List<Hotkey> Hotkeys);

    public async Task<Result<LoadedProfile>> LoadAsync(
        Guid profileId,
        Guid ownerOid,
        CancellationToken ct)
    {
        Profile? profile = await db.Profiles.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == profileId && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        Guid pid = profile.Id;

        List<Hotstring> hotstrings = await db.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync(ct);

        List<Hotkey> hotkeys = await db.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid &&
                        (h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid)))
            .ToListAsync(ct);

        return Result.Success(new LoadedProfile(profile, hotstrings, hotkeys));
    }
}
