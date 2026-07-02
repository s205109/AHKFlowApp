using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record GetHotkeyHistoryVersionQuery(Guid Id, int Version);

internal sealed class GetHotkeyHistoryVersionQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<GetHotkeyHistoryVersionQuery, Result<HotkeyHistoryVersionDto>>
{
    public async Task<Result<HotkeyHistoryVersionDto>> ExecuteAsync(
        GetHotkeyHistoryVersionQuery request,
        CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        EntityHistory? row = await db.EntityHistories
            .AsNoTracking()
            .FirstOrDefaultAsync(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotkey
                && h.EntityId == request.Id
                && h.Version == request.Version, ct);

        if (row is null)
            return Result.NotFound();

        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(row.SnapshotJson);
        if (snapshot is null)
            return Result.Error("Snapshot could not be read.");

        return Result.Success(new HotkeyHistoryVersionDto(row.Version, row.ChangeType, row.CapturedAt, snapshot));
    }
}
