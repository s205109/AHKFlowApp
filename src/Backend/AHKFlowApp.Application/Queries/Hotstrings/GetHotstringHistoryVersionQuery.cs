using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record GetHotstringHistoryVersionQuery(Guid Id, int Version)
    : IRequest<Result<HotstringHistoryVersionDto>>;

internal sealed class GetHotstringHistoryVersionQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<GetHotstringHistoryVersionQuery, Result<HotstringHistoryVersionDto>>
{
    public async Task<Result<HotstringHistoryVersionDto>> Handle(
        GetHotstringHistoryVersionQuery request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        EntityHistory? row = await db.EntityHistories
            .AsNoTracking()
            .FirstOrDefaultAsync(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id
                && h.Version == request.Version, ct);

        if (row is null)
            return Result.NotFound();

        HotstringSnapshot? snapshot = JsonSerializer.Deserialize<HotstringSnapshot>(row.SnapshotJson);
        if (snapshot is null)
            return Result.Error("Snapshot could not be read.");

        return Result.Success(new HotstringHistoryVersionDto(row.Version, row.ChangeType, row.CapturedAt, snapshot));
    }
}
