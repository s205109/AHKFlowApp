using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Categories;

public sealed record ListCategoriesQuery(
    string? Search = null,
    int Page = 1,
    int PageSize = 50);

public sealed class ListCategoriesQueryValidator : AbstractValidator<ListCategoriesQuery>
{
    public ListCategoriesQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}

internal sealed class ListCategoriesQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IUseCaseHandler<ListCategoriesQuery, Result<PagedList<CategoryDto>>>
{
    public async Task<Result<PagedList<CategoryDto>>> ExecuteAsync(ListCategoriesQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        await EnsureSeededOnceAsync(ownerOid, ct);

        IQueryable<Category> query = db.Categories
            .AsNoTracking()
            .Where(c => c.OwnerOid == ownerOid);

        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(c => EF.Functions.Like(c.Name, pattern));
        }

        int total = await query.CountAsync(ct);

        List<CategoryDto> items = await query
            .OrderBy(c => c.Name)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(c => new CategoryDto(c.Id, c.Name, c.CreatedAt, c.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success(new PagedList<CategoryDto>(items, request.Page, request.PageSize, total));
    }

    private async Task EnsureSeededOnceAsync(Guid ownerOid, CancellationToken ct)
    {
        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);

        if (pref?.CategoriesSeededAt is not null)
            return;

        foreach (string name in DefaultCategories.Names)
            db.Categories.Add(Category.Create(ownerOid, name, clock));

        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            pref.MarkCategoriesSeeded(clock);
            db.UserPreferences.Add(pref);
        }
        else
        {
            pref.MarkCategoriesSeeded(clock);
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // Concurrent first-call race: another request already seeded.
            // Detach the pending entries so the subsequent read query works cleanly.
            foreach (Category? entry in db.Categories.Local.ToList())
                db.Entry(entry).State = EntityState.Detached;
            if (pref is not null)
                db.Entry(pref).State = EntityState.Detached;
        }
    }
}
