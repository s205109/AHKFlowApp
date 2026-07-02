using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record PurgeDeletedHotstringCommand(Guid Id) : IRequest<Result>;

internal sealed class PurgeDeletedHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<PurgeDeletedHotstringCommand, Result>
{
    public async Task<Result> Handle(PurgeDeletedHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool liveExists = await db.Hotstrings
            .AnyAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);
        if (liveExists)
            return Result.NotFound();

        List<EntityHistory> rows = await db.EntityHistories
            .Where(h => h.OwnerOid == ownerOid
                && h.EntityType == TrackedEntityType.Hotstring
                && h.EntityId == request.Id)
            .ToListAsync(ct);

        if (!rows.Any(r => r.ChangeType == HistoryChangeType.Delete))
            return Result.NotFound();

        db.EntityHistories.RemoveRange(rows);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
