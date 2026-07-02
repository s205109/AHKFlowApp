using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record GetHotkeyHistoryQuery(Guid Id) : IRequest<Result<HistoryEntryDto[]>>;

internal sealed class GetHotkeyHistoryQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetHotkeyHistoryQuery, Result<HistoryEntryDto[]>>
{
    public async Task<Result<HistoryEntryDto[]>> Handle(GetHotkeyHistoryQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        HistoryEntryDto[] entries = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotkey
                && h.EntityId == request.Id)
            .OrderByDescending(h => h.Version)
            .Select(h => new HistoryEntryDto(h.Version, h.ChangeType, h.CapturedAt))
            .ToArrayAsync(ct);

        if (entries.Length == 0)
        {
            bool liveExists = await db.Hotkeys
                .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
            if (!liveExists)
                return Result.NotFound();
        }

        return Result.Success(entries);
    }
}
