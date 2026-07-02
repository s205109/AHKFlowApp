using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record RevertHotstringCommand(Guid Id, int Version) : IRequest<Result<HotstringDto>>;

internal sealed class RevertHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IRequestHandler<RevertHotstringCommand, Result<HotstringDto>>
{
    public async Task<Result<HotstringDto>> Handle(RevertHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

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

        EntityHistory historyEntry = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Edit, ct);

        Guid[] liveProfileIds = await db.Profiles
            .Where(p => p.OwnerOid == ownerOid && snapshot.ProfileIds.Contains(p.Id))
            .Select(p => p.Id)
            .ToArrayAsync(ct);
        Guid[] liveCategoryIds = await db.Categories
            .Where(c => c.OwnerOid == ownerOid && snapshot.CategoryIds.Contains(c.Id))
            .Select(c => c.Id)
            .ToArrayAsync(ct);

        entity.Update(
            snapshot.Trigger,
            snapshot.Replacement,
            snapshot.Description,
            snapshot.AppliesToAllProfiles,
            snapshot.IsEndingCharacterRequired,
            snapshot.IsTriggerInsideWord,
            clock);

        db.HotstringProfiles.RemoveRange(entity.Profiles);
        entity.Profiles.Clear();
        if (!snapshot.AppliesToAllProfiles)
        {
            foreach (Guid pid in liveProfileIds)
            {
                var junction = HotstringProfile.Create(entity.Id, pid);
                db.HotstringProfiles.Add(junction);
            }
        }

        db.HotstringCategories.RemoveRange(entity.Categories);
        entity.Categories.Clear();
        foreach (Guid cid in liveCategoryIds)
        {
            var junction = HotstringCategory.Create(entity.Id, cid);
            db.HotstringCategories.Add(junction);
        }

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                : Result.Conflict("A hotstring with this trigger already exists.");
        }

        return Result.Success(entity.ToDto());
    }
}
