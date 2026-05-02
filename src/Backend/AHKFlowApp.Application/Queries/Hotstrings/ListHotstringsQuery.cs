using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotstrings;

public sealed record ListHotstringsQuery(
    Guid? ProfileId = null,
    string? Search = null,
    bool IgnoreCase = true,
    int Page = 1,
    int PageSize = 50) : IRequest<Result<PagedList<HotstringDto>>>;

public sealed class ListHotstringsQueryValidator : AbstractValidator<ListHotstringsQuery>
{
    public ListHotstringsQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}

internal sealed class ListHotstringsQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<ListHotstringsQuery, Result<PagedList<HotstringDto>>>
{
    public async Task<Result<PagedList<HotstringDto>>> Handle(ListHotstringsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IQueryable<Hotstring> query = db.Hotstrings
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid);

        if (request.ProfileId.HasValue)
        {
            Guid pid = request.ProfileId.Value;
            query = query.Where(h =>
                h.AppliesToAllProfiles ||
                h.Profiles.Any(p => p.ProfileId == pid));
        }

        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Trigger, pattern) ||
                EF.Functions.Like(h.Replacement, pattern));
        }

        int total = await query.CountAsync(ct);

        List<HotstringDto> items = await query
            .OrderByDescending(h => h.CreatedAt)
            .ThenBy(h => h.Id)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(h => new HotstringDto(
                h.Id,
                h.Profiles.Select(p => p.ProfileId).ToArray(),
                h.AppliesToAllProfiles,
                h.Trigger,
                h.Replacement,
                h.IsEndingCharacterRequired,
                h.IsTriggerInsideWord,
                h.CreatedAt,
                h.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotstringDto>(items, request.Page, request.PageSize, total));
    }
}
