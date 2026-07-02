using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Categories;

public sealed record DeleteCategoryCommand(Guid Id) : IRequest<Result>;

internal sealed class DeleteCategoryCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    IEntityHistoryRecorder recorder)
    : IRequestHandler<DeleteCategoryCommand, Result>
{
    public async Task<Result> Handle(DeleteCategoryCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Category? entity = await db.Categories
            .FirstOrDefaultAsync(c => c.Id == request.Id && c.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        List<Hotstring> linkedHotstrings = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .Where(h => h.OwnerOid == ownerOid && h.Categories.Any(c => c.CategoryId == entity.Id))
            .ToListAsync(ct);
        List<Hotkey> linkedHotkeys = await db.Hotkeys
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .Where(h => h.OwnerOid == ownerOid && h.Categories.Any(c => c.CategoryId == entity.Id))
            .ToListAsync(ct);
        IReadOnlyList<EntityHistory> hotstringHistory =
            await recorder.RecordHotstringsAsync(linkedHotstrings, HistoryChangeType.Edit, ct);
        IReadOnlyList<EntityHistory> hotkeyHistory =
            await recorder.RecordHotkeysAsync(linkedHotkeys, HistoryChangeType.Edit, ct);
        List<EntityHistory> historyEntries = [.. hotstringHistory, .. hotkeyHistory];

        db.Categories.Remove(entity);

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
