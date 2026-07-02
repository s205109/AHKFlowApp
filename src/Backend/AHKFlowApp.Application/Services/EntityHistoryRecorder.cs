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

    public async Task<EntityHistory> RecordHotstringAsync(
        Hotstring entity,
        HistoryChangeType changeType,
        CancellationToken ct)
        => (await RecordHotstringsAsync([entity], changeType, ct))[0];

    public async Task<IReadOnlyList<EntityHistory>> RecordHotstringsAsync(
        IReadOnlyCollection<Hotstring> entities,
        HistoryChangeType changeType,
        CancellationToken ct)
        => await RecordAsync(
            TrackedEntityType.Hotstring,
            [
                .. entities.Select(entity =>
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

                    return new HistorySnapshot(
                        entity.OwnerOid,
                        entity.Id,
                        JsonSerializer.Serialize(snapshot));
                }),
            ],
            changeType,
            ct);

    public async Task<EntityHistory> RecordHotkeyAsync(
        Hotkey entity,
        HistoryChangeType changeType,
        CancellationToken ct)
        => (await RecordHotkeysAsync([entity], changeType, ct))[0];

    public async Task<IReadOnlyList<EntityHistory>> RecordHotkeysAsync(
        IReadOnlyCollection<Hotkey> entities,
        HistoryChangeType changeType,
        CancellationToken ct)
        => await RecordAsync(
            TrackedEntityType.Hotkey,
            [
                .. entities.Select(entity =>
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

                    return new HistorySnapshot(
                        entity.OwnerOid,
                        entity.Id,
                        JsonSerializer.Serialize(snapshot));
                }),
            ],
            changeType,
            ct);

    private async Task<IReadOnlyList<EntityHistory>> RecordAsync(
        TrackedEntityType entityType,
        IReadOnlyList<HistorySnapshot> snapshots,
        HistoryChangeType changeType,
        CancellationToken ct)
    {
        if (snapshots.Count == 0)
            return [];

        Guid[] ownerOids = [.. snapshots.Select(s => s.OwnerOid).Distinct()];
        Guid[] entityIds = [.. snapshots.Select(s => s.EntityId).Distinct()];

        var summaries = await db.EntityHistories
            .Where(h => h.EntityType == entityType
                && ownerOids.Contains(h.OwnerOid)
                && entityIds.Contains(h.EntityId))
            .GroupBy(h => new { h.OwnerOid, h.EntityId })
            .Select(g => new
            {
                g.Key.OwnerOid,
                g.Key.EntityId,
                Count = g.Count(),
                MaxVersion = g.Max(h => h.Version),
            })
            .ToListAsync(ct);

        Dictionary<(Guid OwnerOid, Guid EntityId), (int Count, int NextVersion)> stateByEntity =
            summaries.ToDictionary(
                x => (x.OwnerOid, x.EntityId),
                x => (x.Count, x.MaxVersion + 1));

        List<EntityHistory> entries = [];
        Dictionary<(Guid OwnerOid, Guid EntityId), int> excessByEntity = [];
        foreach (HistorySnapshot snapshot in snapshots)
        {
            (Guid OwnerOid, Guid EntityId) key = (snapshot.OwnerOid, snapshot.EntityId);
            (int count, int nextVersion) = stateByEntity.TryGetValue(key, out (int Count, int NextVersion) state)
                ? state
                : (0, 1);

            var entry = EntityHistory.Create(
                snapshot.OwnerOid, entityType, snapshot.EntityId, nextVersion, changeType,
                CurrentSchemaVersion, snapshot.SnapshotJson, clock);
            entries.Add(entry);

            int newCount = count + 1;
            int excess = newCount - MaxVersionsPerItem;
            if (excess > 0)
                excessByEntity[key] = excess;

            stateByEntity[key] = (newCount, nextVersion + 1);
        }

        db.EntityHistories.AddRange(entries);

        foreach (KeyValuePair<(Guid OwnerOid, Guid EntityId), int> request in excessByEntity)
        {
            List<EntityHistory> oldest = await db.EntityHistories
                .Where(h => h.OwnerOid == request.Key.OwnerOid
                    && h.EntityType == entityType
                    && h.EntityId == request.Key.EntityId)
                .OrderBy(h => h.Version)
                .Take(request.Value)
                .ToListAsync(ct);
            db.EntityHistories.RemoveRange(oldest);
        }

        return entries;
    }

    private sealed record HistorySnapshot(Guid OwnerOid, Guid EntityId, string SnapshotJson);
}
