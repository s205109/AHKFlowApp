using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Categories;

public sealed record DeleteCategoryCommand(Guid Id);

internal sealed class DeleteCategoryCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IUseCaseHandler<DeleteCategoryCommand, Result>
{
    public async Task<Result> ExecuteAsync(DeleteCategoryCommand request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Category? entity = await db.Categories
            .FirstOrDefaultAsync(c => c.Id == request.Id && c.OwnerOid == ownerOid, ct);

        if (entity is null)
            return Result.NotFound();

        db.Categories.Remove(entity);
        await db.SaveChangesAsync(ct);
        return Result.Success();
    }
}
