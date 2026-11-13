using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
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

        if (entity is null)
            return Result.NotFound();

        HotstringDto dto = entity.ToDto();

        // Backlog 175: only an item that applies to no profile names its broken rules.
        return Result.Success(entity is { AppliesToAllProfiles: false, Profiles.Count: 0 }
            ? dto with { BrokenRules = DefinitionRuleCheck.BrokenRules(entity) }
            : dto);
    }
}
