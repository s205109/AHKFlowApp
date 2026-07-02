using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record ListDeletedHotstringsQuery() : IRequest<Result<DeletedHotstringDto[]>>;

internal sealed class ListDeletedHotstringsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<ListDeletedHotstringsQuery, Result<DeletedHotstringDto[]>>
{
    public async Task<Result<DeletedHotstringDto[]>> Handle(
        ListDeletedHotstringsQuery request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        List<EntityHistory> tombstones = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.ChangeType == HistoryChangeType.Delete
                && !db.Hotstrings.Any(x => x.OwnerOid == ownerOid && x.Id == h.EntityId)
                && !db.EntityHistories.Any(newer => newer.OwnerOid == ownerOid
                    && newer.EntityType == h.EntityType
                    && newer.EntityId == h.EntityId
                    && newer.Version > h.Version))
            .OrderByDescending(h => h.CapturedAt)
            .ToListAsync(ct);

        DeletedHotstringDto[] items =
        [
            .. tombstones
                .Select(row => (Row: row, Snapshot: JsonSerializer.Deserialize<HotstringSnapshot>(row.SnapshotJson)))
                .Where(x => x.Snapshot is not null)
                .Select(x => new DeletedHotstringDto(
                    x.Row.EntityId,
                    x.Snapshot!.Trigger,
                    x.Snapshot.Replacement,
                    x.Snapshot.Description,
                    x.Row.CapturedAt))
        ];

        return Result.Success(items);
    }
}
