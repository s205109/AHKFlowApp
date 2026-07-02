using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Services;

internal sealed class EntityHistoryRecorder(IAppDbContext db, TimeProvider clock) : IEntityHistoryRecorder
{
    internal const int MaxVersionsPerItem = 50;
    internal const int CurrentSchemaVersion = 1;

    public Task<EntityHistory> RecordHotstringAsync(Hotstring entity, HistoryChangeType changeType, CancellationToken ct)
    {
        HotstringSnapshot snapshot = new(
            entity.Trigger,
            entity.Replacement,
            entity.Description,
            entity.AppliesToAllProfiles,
            entity.IsEndingCharacterRequired,
            entity.IsTriggerInsideWord,
            [.. entity.Profiles.Select(p => p.ProfileId)],
            [.. entity.Categories.Select(c => c.CategoryId)],
            entity.CreatedAt,
            entity.UpdatedAt);

        return RecordAsync(
            entity.OwnerOid, TrackedEntityType.Hotstring, entity.Id, changeType,
            JsonSerializer.Serialize(snapshot), ct);
    }

    public Task<EntityHistory> RecordHotkeyAsync(Hotkey entity, HistoryChangeType changeType, CancellationToken ct)
    {
        HotkeySnapshot snapshot = new(
            entity.Description,
            entity.Key,
            entity.Ctrl,
            entity.Alt,
            entity.Shift,
            entity.Win,
            entity.Action,
            entity.Parameters,
            entity.AppliesToAllProfiles,
            [.. entity.Profiles.Select(p => p.ProfileId)],
            [.. entity.Categories.Select(c => c.CategoryId)],
            entity.CreatedAt,
            entity.UpdatedAt);

        return RecordAsync(
            entity.OwnerOid, TrackedEntityType.Hotkey, entity.Id, changeType,
            JsonSerializer.Serialize(snapshot), ct);
    }

    private async Task<EntityHistory> RecordAsync(
        Guid ownerOid,
        TrackedEntityType entityType,
        Guid entityId,
        HistoryChangeType changeType,
        string snapshotJson,
        CancellationToken ct)
    {
        List<EntityHistory> existing = await db.EntityHistories
            .Where(h => h.EntityType == entityType && h.EntityId == entityId)
            .OrderBy(h => h.Version)
            .ToListAsync(ct);

        int nextVersion = (existing.Count > 0 ? existing[^1].Version : 0) + 1;

        var entry = EntityHistory.Create(
            ownerOid, entityType, entityId, nextVersion, changeType,
            CurrentSchemaVersion, snapshotJson, clock);
        db.EntityHistories.Add(entry);

        int excess = existing.Count + 1 - MaxVersionsPerItem;
        if (excess > 0)
            db.EntityHistories.RemoveRange(existing.Take(excess));

        return entry;
    }
}
