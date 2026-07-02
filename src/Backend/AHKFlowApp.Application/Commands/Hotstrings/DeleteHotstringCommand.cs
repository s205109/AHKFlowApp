using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record DeleteHotstringCommand(Guid Id) : IRequest<Result>;

internal sealed class DeleteHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    IEntityHistoryRecorder recorder)
    : IRequestHandler<DeleteHotstringCommand, Result>
{
    public async Task<Result> Handle(DeleteHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        EntityHistory tombstone = await recorder.RecordHotstringAsync(entity, HistoryChangeType.Delete, ct);
        db.Hotstrings.Remove(entity);

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
