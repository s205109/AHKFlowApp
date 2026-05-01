using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotkeys;

public sealed record DeleteHotkeyCommand(Guid Id) : IRequest<Result>;

internal sealed class DeleteHotkeyCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<DeleteHotkeyCommand, Result>
{
    public async Task<Result> Handle(DeleteHotkeyCommand request, CancellationToken ct)
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
