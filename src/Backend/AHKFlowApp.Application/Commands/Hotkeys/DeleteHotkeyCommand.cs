using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record DeleteHotkeyCommand(Guid Id);

internal sealed class DeleteHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    IEntityHistoryRecorder recorder)
    : IUseCaseHandler<DeleteHotkeyCommand, Result>
{
    public async Task<Result> ExecuteAsync(DeleteHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        EntityHistory tombstone = await recorder.RecordHotkeyAsync(entity, HistoryChangeType.Delete, ct);
        db.Hotkeys.Remove(entity);

        try
        {
            await db.SaveWithHistoryRetryAsync(tombstone, ct);
        }
        catch (DbUpdateException ex) when (ex.IsHistoryVersionConflict())
        {
            return Result.Conflict("The item was modified concurrently. Retry the operation.");
        }

        return Result.Success();
    }
}
