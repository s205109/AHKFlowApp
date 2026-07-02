using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record DeleteProfileCommand(Guid Id);

internal sealed class DeleteProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    IEntityHistoryRecorder recorder)
    : IUseCaseHandler<DeleteProfileCommand, Result>
{
    public async Task<Result> ExecuteAsync(DeleteProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        List<Hotstring> linkedHotstrings = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .Where(h => h.OwnerOid == ownerOid && h.Profiles.Any(p => p.ProfileId == profile.Id))
            .ToListAsync(ct);
        List<Hotkey> linkedHotkeys = await db.Hotkeys
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .Where(h => h.OwnerOid == ownerOid && h.Profiles.Any(p => p.ProfileId == profile.Id))
            .ToListAsync(ct);
        IReadOnlyList<EntityHistory> hotstringHistory =
            await recorder.RecordHotstringsAsync(linkedHotstrings, HistoryChangeType.Edit, ct);
        IReadOnlyList<EntityHistory> hotkeyHistory =
            await recorder.RecordHotkeysAsync(linkedHotkeys, HistoryChangeType.Edit, ct);
        List<EntityHistory> historyEntries = [.. hotstringHistory, .. hotkeyHistory];

        db.Profiles.Remove(profile);

        try
        {
            await db.SaveWithHistoryRetryAsync(historyEntries, ct);
        }
        catch (DbUpdateException ex) when (ex.IsHistoryVersionConflict())
        {
            return Result.Conflict("One or more linked items were modified concurrently. Retry the operation.");
        }

        return Result.Success();
    }
}
