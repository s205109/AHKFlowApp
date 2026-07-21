using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record RevertHotkeyCommand(Guid Id, int Version);

internal sealed class RevertHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IUseCaseHandler<RevertHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> ExecuteAsync(RevertHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

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

        EntityHistory historyEntry = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Edit, ct);

        Guid[] liveProfileIds = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid && snapshot.ProfileIds.Contains(p.Id))
            .Select(p => p.Id)
            .ToArrayAsync(ct);
        Guid[] liveCategoryIds = await db.Categories
            .Where(c => c.OwnerOid == ownerOid && snapshot.CategoryIds.Contains(c.Id))
            .Select(c => c.Id)
            .ToArrayAsync(ct);

        entity.Update(
            new HotkeyDefinition(
                snapshot.Description,
                snapshot.Key,
                snapshot.Ctrl,
                snapshot.Alt,
                snapshot.Shift,
                snapshot.Win,
                snapshot.Action,
                snapshot.Parameters,
                snapshot.AppliesToAllProfiles),
            clock);

        db.HotkeyProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();
        if (!snapshot.AppliesToAllProfiles)
        {
            foreach (Guid pid in liveProfileIds)
            {
                var junction = HotkeyProfile.Create(entity.Id, pid);
                db.HotkeyProfiles.Add(junction);
            }
        }

        db.HotkeyCategories.RemoveRange(entity.Categories);
        entity.Categories.Clear();
        foreach (Guid cid in liveCategoryIds)
        {
            var junction = HotkeyCategory.Create(entity.Id, cid);
            db.HotkeyCategories.Add(junction);
        }

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict("A hotkey with this key + modifier combination already exists.");
        }

        return Result.Success(entity.ToDto());
    }
}
