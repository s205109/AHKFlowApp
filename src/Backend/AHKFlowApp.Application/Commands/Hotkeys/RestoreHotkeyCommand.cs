using System.Text.Json;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record RestoreHotkeyCommand(Guid Id);

internal sealed class RestoreHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    IEntityHistoryRecorder recorder)
    : IUseCaseHandler<RestoreHotkeyCommand, Result<HotkeyDto>>
{
    public async Task<Result<HotkeyDto>> ExecuteAsync(RestoreHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool liveExists = await db.Hotkeys
            .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
        if (liveExists)
            return Result.Conflict("The hotkey already exists - nothing to restore.");

        EntityHistory? tombstone = await db.EntityHistories
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotkey
                && h.EntityId == request.Id
                && h.ChangeType == HistoryChangeType.Delete)
            .OrderByDescending(h => h.Version)
            .FirstOrDefaultAsync(ct);

        if (tombstone is null)
            return Result.NotFound();

        HotkeySnapshot? snapshot = JsonSerializer.Deserialize<HotkeySnapshot>(tombstone.SnapshotJson);
        if (snapshot is null)
            return Result.Error("Snapshot could not be read.");

        Guid[] liveCategoryIds = await db.Categories
            .Where(c => c.OwnerOid == ownerOid && snapshot.CategoryIds.Contains(c.Id))
            .Select(c => c.Id)
            .ToArrayAsync(ct);

        // The converted definition is what the Emitter will read, so it is what the rules judge.
        HotkeyDefinition definition = LegacyHotkeySnapshotConverter.ToDefinition(snapshot);

        // The rules a new save must pass (backlog 162). A Snapshot that fails them still comes
        // back, but attached to no Profile, so it reaches no generated script until the Owner
        // repairs it. ADR-0021 holds the reasoning.
        string[] warnings = [.. DefinitionRuleCheck.Check(definition).Select(e => e.ErrorMessage)];
        bool keepProfileScope = warnings.Length == 0;
        if (!keepProfileScope)
            definition = definition with { AppliesToAllProfiles = false };

        var entity = Hotkey.Restore(
            request.Id,
            ownerOid,
            definition,
            snapshot.CreatedAt,
            clock);

        db.Hotkeys.Add(entity);

        if (keepProfileScope && !snapshot.AppliesToAllProfiles)
        {
            // Read here rather than above: this is the only reader, so a Snapshot that failed the
            // rules, or one that applied to every Profile, does not pay for the round trip.
            Guid[] liveProfileIds = await db.Profiles
                .Where(p => p.OwnerOid == ownerOid && snapshot.ProfileIds.Contains(p.Id))
                .Select(p => p.Id)
                .ToArrayAsync(ct);

            foreach (Guid pid in liveProfileIds)
                db.HotkeyProfiles.Add(HotkeyProfile.Create(entity.Id, pid));
        }

        foreach (Guid cid in liveCategoryIds)
            db.HotkeyCategories.Add(HotkeyCategory.Create(entity.Id, cid));

        EntityHistory historyEntry = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Restore, ct);

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntry, ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            return ex.IsHistoryVersionConflict()
                ? Result.Conflict("The item was modified concurrently. Retry the operation.")
                // Read from the entity, not the snapshot: a pre-W1 snapshot carries no context, and
                // the converter is what turns that into "fires everywhere".
                : Result.Conflict(
                    HotkeyConflictMessages.Duplicate(entity.ContextMatchType, entity.ContextValue));
        }

        return Result.Success(entity.ToDto() with { RestoreWarnings = warnings.Length > 0 ? warnings : null });
    }
}
