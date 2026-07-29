using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.KnownShortcuts;

/// <summary>Stops warning about one built-in use. Other uses of the same keys still warn.</summary>
public sealed record IgnoreKnownShortcutCommand(string ShortcutId, string UsedBy);

internal sealed class IgnoreKnownShortcutCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<IgnoreKnownShortcutCommand, Result>
{
    public async Task<Result> ExecuteAsync(IgnoreKnownShortcutCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        // Only a built-in use can be ignored. An owner removes their own record by deleting it.
        bool builtInUseExists = KnownShortcutCatalog.All.Any(s =>
            s.Id == request.ShortcutId && s.Uses.Any(u => u.UsedBy == request.UsedBy));

        if (!builtInUseExists)
            return Result.NotFound();

        bool alreadyIgnored = await db.IgnoredKnownShortcuts.AnyAsync(
            i => i.OwnerOid == ownerOid
              && i.ShortcutId == request.ShortcutId
              && i.UsedBy == request.UsedBy,
            ct);

        // The owner asked for a state, not for a transition, so already being there is success.
        if (alreadyIgnored)
            return Result.Success();

        db.IgnoredKnownShortcuts.Add(
            IgnoredKnownShortcut.Create(ownerOid, request.ShortcutId, request.UsedBy, clock));

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // Another request already wrote the same ignore. The owner asked for a state and the
            // state is there, so this is success — the promised no-op, not a 409 and not a 500.
            return Result.Success();
        }

        return Result.Success();
    }
}
