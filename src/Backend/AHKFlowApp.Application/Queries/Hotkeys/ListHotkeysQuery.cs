using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record ListHotkeysQuery(
    Guid? ProfileId = null,
    string? Search = null,
    bool IgnoreCase = true,
    int Page = 1,
    int PageSize = 50) : IRequest<Result<PagedList<HotkeyDto>>>;

public sealed class ListHotkeysQueryValidator : AbstractValidator<ListHotkeysQuery>
{
    public ListHotkeysQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
    }
}

internal sealed class ListHotkeysQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser)
    : IRequestHandler<ListHotkeysQuery, Result<PagedList<HotkeyDto>>>
{
    public async Task<Result<PagedList<HotkeyDto>>> Handle(ListHotkeysQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        IQueryable<Hotkey> query = db.Hotkeys
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
                EF.Functions.Like(h.Description, pattern) ||
                EF.Functions.Like(h.Key, pattern) ||
                EF.Functions.Like(h.Parameters, pattern));
        }

        int total = await query.CountAsync(ct);

        List<HotkeyDto> items = await query
            .Include(h => h.Profiles)
            .OrderByDescending(h => h.CreatedAt)
            .ThenBy(h => h.Id)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(h => new HotkeyDto(
                h.Id,
                h.Profiles.Select(p => p.ProfileId).ToArray(),
                h.AppliesToAllProfiles,
                h.Description,
                h.Key,
                h.Ctrl,
                h.Alt,
                h.Shift,
                h.Win,
                h.Action,
                h.Parameters,
                h.CreatedAt,
                h.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotkeyDto>(items, request.Page, request.PageSize, total));
    }
}
