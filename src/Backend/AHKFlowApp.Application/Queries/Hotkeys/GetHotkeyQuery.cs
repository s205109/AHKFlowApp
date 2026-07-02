using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
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

        return entity is null
            ? Result.NotFound()
            : Result.Success(entity.ToDto());
    }
}
