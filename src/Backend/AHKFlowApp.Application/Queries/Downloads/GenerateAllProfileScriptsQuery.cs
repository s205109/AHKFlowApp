using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GenerateAllProfileScriptsQuery : IRequest<Result<IReadOnlyList<ProfileScript>>>;

internal sealed class GenerateAllProfileScriptsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    AhkScriptGenerator generator)
    : IRequestHandler<GenerateAllProfileScriptsQuery, Result<IReadOnlyList<ProfileScript>>>
{
    public async Task<Result<IReadOnlyList<ProfileScript>>> Handle(
        GenerateAllProfileScriptsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        List<Profile> profiles = await db.Profiles.AsNoTracking()
            .Where(p => p.OwnerOid == ownerOid)
            .OrderBy(p => p.Name)
            .ToListAsync(ct);

        if (profiles.Count == 0)
            return Result.Success<IReadOnlyList<ProfileScript>>([]);

        List<Hotstring> allHotstrings = await db.Hotstrings.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .Include(h => h.Profiles)
            .ToListAsync(ct);

        List<Hotkey> allHotkeys = await db.Hotkeys.AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .Include(h => h.Profiles)
            .ToListAsync(ct);

        List<ProfileScript> scripts = new(profiles.Count);
        HashSet<string> usedNames = new(StringComparer.OrdinalIgnoreCase);

        foreach (Profile profile in profiles)
        {
            Guid pid = profile.Id;

            IEnumerable<Hotstring> hotstringsForProfile = allHotstrings.Where(h =>
                h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid));

            IEnumerable<Hotkey> hotkeysForProfile = allHotkeys.Where(h =>
                h.AppliesToAllProfiles || h.Profiles.Any(p => p.ProfileId == pid));

            string content = generator.Generate(profile, hotstringsForProfile, hotkeysForProfile);
            string fileName = NextUniqueFileName(profile.Name, usedNames);
            scripts.Add(new ProfileScript(fileName, content));
        }

        return Result.Success<IReadOnlyList<ProfileScript>>(scripts);
    }

    private static string NextUniqueFileName(string profileName, HashSet<string> usedNames)
    {
        string baseStem = AhkFileNaming.ToSafeStem(profileName);
        string candidate = $"ahkflow_{baseStem}.ahk";
        int suffix = 2;
        while (!usedNames.Add(candidate))
        {
            candidate = $"ahkflow_{baseStem}_{suffix}.ahk";
            suffix++;
        }
        return candidate;
    }
}
