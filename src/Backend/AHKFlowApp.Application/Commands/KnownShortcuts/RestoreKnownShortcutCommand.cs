using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.KnownShortcuts;

/// <summary>Warns about a built-in use again.</summary>
public sealed record RestoreKnownShortcutCommand(string ShortcutId, string UsedBy);

internal sealed class RestoreKnownShortcutCommandHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<RestoreKnownShortcutCommand, Result>
{
    public async Task<Result> ExecuteAsync(RestoreKnownShortcutCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IgnoredKnownShortcut? ignore = await db.IgnoredKnownShortcuts.FirstOrDefaultAsync(
            i => i.OwnerOid == ownerOid
              && i.ShortcutId == request.ShortcutId
              && i.UsedBy == request.UsedBy,
            ct);

        // No row means the use already warns. The owner asked for that state, so this is success.
        // Deleting twice needs no race guard for the same reason.
        if (ignore is null)
            return Result.Success();

        db.IgnoredKnownShortcuts.Remove(ignore);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
