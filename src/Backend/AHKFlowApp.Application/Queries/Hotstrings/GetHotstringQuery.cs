using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringQuery(Guid Id);

internal sealed class GetHotstringQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<GetHotstringQuery, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> ExecuteAsync(GetHotstringQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .AsNoTracking()
            .Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        return entity is null
            ? Result.NotFound()
            : Result.Success(entity.ToDto());
    }
}
