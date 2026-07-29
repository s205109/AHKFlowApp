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
        if (ignore is null)
            return Result.Success();

        db.IgnoredKnownShortcuts.Remove(ignore);

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            // Two requests can read the same row and then both delete it. The second DELETE affects
            // no rows, which EF Core reports as a concurrency conflict. The row is gone either way,
            // so the owner got the state they asked for.
        }

        return Result.Success();
    }
}
