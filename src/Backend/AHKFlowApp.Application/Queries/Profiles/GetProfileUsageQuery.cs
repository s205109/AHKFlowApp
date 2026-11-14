using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Profiles;

public sealed record GetProfileUsageQuery(Guid Id);

/// <summary>
/// Counts the owner's hotstrings and hotkeys that a delete would leave applying to no profile.
/// An item counts when this profile is its only link and it does not apply to all profiles.
/// The filters include the one in <c>DeleteProfileCommandHandler</c>, so the counts are a
/// subset of the items a delete changes.
/// </summary>
internal sealed class GetProfileUsageQueryHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<GetProfileUsageQuery, Result<ProfileUsageDto>>
{
    public async Task<Result<ProfileUsageDto>> ExecuteAsync(GetProfileUsageQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool exists = await db.Profiles
            .AnyAsync(p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);

        if (!exists)
            return Result.NotFound();

        int hotstringCount = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid
                && !h.AppliesToAllProfiles
                && h.Profiles.Any(p => p.ProfileId == request.Id)
                && h.Profiles.All(p => p.ProfileId == request.Id))
            .CountAsync(ct);
        int hotkeyCount = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid
                && !h.AppliesToAllProfiles
                && h.Profiles.Any(p => p.ProfileId == request.Id)
                && h.Profiles.All(p => p.ProfileId == request.Id))
            .CountAsync(ct);

        return Result.Success(new ProfileUsageDto(hotstringCount, hotkeyCount));
    }
}
