using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Hotstrings;

public sealed record DeleteHotstringCommand(Guid Id) : IRequest<Result>;

internal sealed class DeleteHotstringCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<DeleteHotstringCommand, Result>
{
    public async Task<Result> Handle(DeleteHotstringCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Hotstring? entity = await db.Hotstrings
            .FirstOrDefaultAsync(h => h.Id == request.Id && h.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        db.Hotstrings.Remove(entity);
        await db.SaveChangesAsync(ct);

        return Result.Success();
    }
}
