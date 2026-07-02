using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Categories;

public sealed record GetCategoryQuery(Guid Id);

internal sealed class GetCategoryQueryHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<GetCategoryQuery, Result<CategoryDto>>
{
    public async Task<Result<CategoryDto>> ExecuteAsync(GetCategoryQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        Category? entity = await db.Categories
            .AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == request.Id && c.OwnerOid == ownerOid, ct);

        return entity is null ? Result.NotFound() : Result.Success(entity.ToDto());
    }
}
