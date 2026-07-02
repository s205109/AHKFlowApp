using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record DeleteHotkeyCommand(Guid Id);

internal sealed class DeleteHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<DeleteHotkeyCommand, Result>
{
    public async Task<Result> ExecuteAsync(DeleteHotkeyCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotkey? entity = await db.Hotkeys
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        db.Hotkeys.Remove(entity);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
