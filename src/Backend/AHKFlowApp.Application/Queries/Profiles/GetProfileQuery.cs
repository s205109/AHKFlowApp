using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Profiles;

public sealed record GetProfileQuery(Guid Id);

internal sealed class GetProfileQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<GetProfileQuery, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> ExecuteAsync(GetProfileQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.AsNoTracking().FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        return profile is null ? Result.NotFound() : Result.Success(profile.ToDto());
    }
}
