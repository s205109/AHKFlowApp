using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record ListDeletedHotkeysQuery();

internal sealed class ListDeletedHotkeysQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<ListDeletedHotkeysQuery, Result<DeletedHotkeyDto[]>>
{
    internal const int MaxDeletedItems = 500;

    public async Task<Result<DeletedHotkeyDto[]>> ExecuteAsync(ListDeletedHotkeysQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        List<EntityHistory> tombstones = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotkey
                && h.ChangeType == HistoryChangeType.Delete
                && !db.Hotkeys.Any(x => x.OwnerOid == ownerOid && x.Id == h.EntityId)
                && !db.EntityHistories.Any(newer => newer.OwnerOid == ownerOid
                    && newer.EntityType == h.EntityType
                    && newer.EntityId == h.EntityId
                    && newer.Version > h.Version))
            .OrderByDescending(h => h.CapturedAt)
            .Take(MaxDeletedItems)
            .ToListAsync(ct);

        DeletedHotkeyDto[] items =
        [
            .. tombstones
                .Select(row => (Row: row, Snapshot: JsonSerializer.Deserialize<HotkeySnapshot>(row.SnapshotJson)))
                .Where(x => x.Snapshot is not null)
                .Select(x => new DeletedHotkeyDto(
                    x.Row.EntityId,
                    x.Snapshot!.Description,
                    x.Snapshot.Key,
                    x.Snapshot.Ctrl,
                    x.Snapshot.Alt,
                    x.Snapshot.Shift,
                    x.Snapshot.Win,
                    x.Row.CapturedAt))
        ];

        return Result.Success(items);
    }
}
