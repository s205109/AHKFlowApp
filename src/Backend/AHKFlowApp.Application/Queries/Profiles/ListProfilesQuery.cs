using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Profiles;

public sealed record ListProfilesQuery;

internal sealed class ListProfilesQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<ListProfilesQuery, Result<IReadOnlyList<ProfileDto>>>
{
    public async Task<Result<IReadOnlyList<ProfileDto>>> ExecuteAsync(ListProfilesQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        await db.EnsureDefaultProfileAsync(ownerOid, clock, ct);

        List<ProfileDto> items = await db.Profiles
            .AsNoTracking()
            .Where(p => p.OwnerOid == ownerOid)
            .OrderByDescending(p => p.IsDefault)
            .ThenBy(p => p.Name)
            .Select(p => new ProfileDto(
                p.Id, p.Name, p.IsDefault, p.HeaderTemplate, p.FooterTemplate, p.CreatedAt, p.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success<IReadOnlyList<ProfileDto>>(items);
    }
}
