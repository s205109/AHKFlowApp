using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.KnownShortcuts;

/// <summary>Removes one of the owner's own records.</summary>
public sealed record DeleteCustomKnownShortcutCommand(Guid Id);

internal sealed class DeleteCustomKnownShortcutCommandHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<DeleteCustomKnownShortcutCommand, Result>
{
    public async Task<Result> ExecuteAsync(DeleteCustomKnownShortcutCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        // Filtered by owner, so another owner's record is simply not found. A separate Forbidden
        // would confirm to a stranger that the record exists.
        CustomKnownShortcut? record = await db.CustomKnownShortcuts
            .FirstOrDefaultAsync(s => s.Id == request.Id && s.OwnerOid == ownerOid, ct);

        if (record is null)
            return Result.NotFound();

        db.CustomKnownShortcuts.Remove(record);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
