using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record GetHotkeyQuery(Guid Id);

internal sealed class GetHotkeyQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<GetHotkeyQuery, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> ExecuteAsync(GetHotkeyQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .AsNoTracking()
            .Include(h => h.Profiles)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        HotkeyDto dto = entity.ToDto();

        // Backlog 175: only an item that applies to no profile names its broken rules.
        return Result.Success(entity is { AppliesToAllProfiles: false, Profiles.Count: 0 }
            ? dto with { BrokenRules = DefinitionRuleCheck.BrokenRules(entity) }
            : dto);
    }
}
