using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Preferences;

public sealed record GetUserPreferenceQuery;

internal sealed class GetUserPreferenceQueryHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<GetUserPreferenceQuery, Result<UserPreferenceDto>>
{
    public async Task<Result<UserPreferenceDto>> ExecuteAsync(GetUserPreferenceQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        UserPreference? pref = await db.UserPreferences
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);

        return pref is null ? Result.NotFound() : Result.Success(pref.ToDto());
    }
}
