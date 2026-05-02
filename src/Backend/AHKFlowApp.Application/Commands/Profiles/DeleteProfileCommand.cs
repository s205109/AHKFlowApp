using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Profiles;

public sealed record DeleteProfileCommand(Guid Id) : IRequest<Result>;

internal sealed class DeleteProfileCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<DeleteProfileCommand, Result>
{
    public async Task<Result> Handle(DeleteProfileCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Profile? profile = await db.Profiles.FirstOrDefaultAsync(
            p => p.Id == request.Id && p.OwnerOid == ownerOid, ct);
        if (profile is null)
            return Result.NotFound();

        db.Profiles.Remove(profile);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
