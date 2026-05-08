using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Downloads;

public sealed record GenerateProfileScriptQuery(Guid ProfileId) : IRequest<Result<ProfileScript>>;

internal sealed class GenerateProfileScriptQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    AhkScriptGenerator generator)
    : IRequestHandler<GenerateProfileScriptQuery, Result<ProfileScript>>
{
    public async Task<Result<ProfileScript>> Handle(GenerateProfileScriptQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.AsNoTracking().FirstOrDefaultAsync(
            p => p.Id == request.ProfileId && p.OwnerOid == ownerOid, ct);
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

        string content = generator.Generate(profile, hotstrings, hotkeys);
        string fileName = AhkFileNaming.FileName(profile.Name);
        return Result.Success(new ProfileScript(fileName, content));
    }
}
