using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringHistoryQuery(Guid Id);

internal sealed class GetHotstringHistoryQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<GetHotstringHistoryQuery, Result<HistoryEntryDto[]>>
{
    public async Task<Result<HistoryEntryDto[]>> ExecuteAsync(GetHotstringHistoryQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        HistoryEntryDto[] entries = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id)
            .OrderByDescending(h => h.Version)
            .Select(h => new HistoryEntryDto(h.Version, h.ChangeType, h.CapturedAt))
            .ToArrayAsync(ct);

        if (entries.Length == 0)
        {
            bool liveExists = await db.Hotstrings
                .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
            if (!liveExists)
                return Result.NotFound();
        }

        return Result.Success(entries);
    }
}
