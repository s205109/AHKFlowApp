using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Categories;

public sealed record GetCategoryUsageQuery(Guid Id);

/// <summary>
/// Counts the owner's hotstrings and hotkeys linked to one category. The filters match
/// <c>DeleteCategoryCommandHandler</c>, so the counts are the items a delete would change.
/// </summary>
internal sealed class GetCategoryUsageQueryHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<GetCategoryUsageQuery, Result<CategoryUsageDto>>
{
    public async Task<Result<CategoryUsageDto>> ExecuteAsync(GetCategoryUsageQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool exists = await db.Categories
            .AnyAsync(c => c.Id == request.Id && c.OwnerOid == ownerOid, ct);

        if (!exists)
            return Result.NotFound();

        int hotstringCount = await db.Hotstrings
            .Where(h => h.OwnerOid == ownerOid && h.Categories.Any(c => c.CategoryId == request.Id))
            .CountAsync(ct);
        int hotkeyCount = await db.Hotkeys
            .Where(h => h.OwnerOid == ownerOid && h.Categories.Any(c => c.CategoryId == request.Id))
            .CountAsync(ct);

        return Result.Success(new CategoryUsageDto(hotstringCount, hotkeyCount));
    }
}
