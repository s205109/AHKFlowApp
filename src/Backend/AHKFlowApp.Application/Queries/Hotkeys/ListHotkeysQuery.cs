using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Hotkeys;

public sealed record ListHotkeysQuery(
    Guid? ProfileId = null,
    string? Search = null,
    int Page = 1,
    int PageSize = 50,
    string? SortField = null,
    bool SortDescending = true,
    string? DescriptionFilter = null,
    string? KeyFilter = null,
    string? ParametersFilter = null,
    HotkeyAction? Action = null,
    bool? AppliesToAllProfiles = null,
    bool? Ctrl = null,
    bool? Alt = null,
    bool? Shift = null,
    bool? Win = null,
    IReadOnlyList<Guid>? CategoryIds = null) : IRequest<Result<PagedList<HotkeyDto>>>;

public sealed class ListHotkeysQueryValidator : AbstractValidator<ListHotkeysQuery>
{
    private static readonly string[] AllowedSortFields =
    [
        "createdat", "updatedat", "description", "key",
        "ctrl", "alt", "shift", "win", "action", "parameters"
    ];

    public ListHotkeysQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
        RuleFor(x => x.DescriptionFilter).MaximumLength(200);
        RuleFor(x => x.KeyFilter).MaximumLength(200);
        RuleFor(x => x.ParametersFilter).MaximumLength(200);
        RuleFor(x => x.SortField)
            .Must(f => string.IsNullOrEmpty(f) ||
                       AllowedSortFields.Contains(f.Trim().ToLowerInvariant(),
                           StringComparer.OrdinalIgnoreCase))
            .WithMessage($"SortField must be one of: {string.Join(", ", AllowedSortFields)}");
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

        // Case-insensitive: relies on the database collation (SQL_Latin1_General_CP1_CI_AS).
        // Do not add an ignoreCase parameter — see docs/architecture/search-semantics.md.
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Description, pattern) ||
                EF.Functions.Like(h.Key, pattern) ||
                EF.Functions.Like(h.Parameters, pattern));
        }

        if (!string.IsNullOrWhiteSpace(request.DescriptionFilter))
        {
            string pattern = $"%{request.DescriptionFilter.Trim()}%";
            query = query.Where(h => EF.Functions.Like(h.Description, pattern));
        }

        if (!string.IsNullOrWhiteSpace(request.KeyFilter))
        {
            string pattern = $"%{request.KeyFilter.Trim()}%";
            query = query.Where(h => EF.Functions.Like(h.Key, pattern));
        }

        if (!string.IsNullOrWhiteSpace(request.ParametersFilter))
        {
            string pattern = $"%{request.ParametersFilter.Trim()}%";
            query = query.Where(h => EF.Functions.Like(h.Parameters ?? "", pattern));
        }

        if (request.Action.HasValue)
            query = query.Where(h => h.Action == request.Action.Value);

        if (request.AppliesToAllProfiles.HasValue)
            query = query.Where(h => h.AppliesToAllProfiles == request.AppliesToAllProfiles.Value);

        if (request.Ctrl.HasValue)
            query = query.Where(h => h.Ctrl == request.Ctrl.Value);

        if (request.Alt.HasValue)
            query = query.Where(h => h.Alt == request.Alt.Value);

        if (request.Shift.HasValue)
            query = query.Where(h => h.Shift == request.Shift.Value);

        if (request.Win.HasValue)
            query = query.Where(h => h.Win == request.Win.Value);

        if (request.CategoryIds is { Count: > 0 })
        {
            Guid[] ids = request.CategoryIds.Distinct().ToArray();
            query = query.Where(h => h.Categories.Any(hc => ids.Contains(hc.CategoryId)));
        }

        int total = await query.CountAsync(ct);

        List<HotkeyDto> items = await ApplySorting(query, request.SortField, request.SortDescending)
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
                h.UpdatedAt,
                h.Categories.Select(c => c.CategoryId).ToArray()))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotkeyDto>(items, request.Page, request.PageSize, total));
    }

    private static IOrderedQueryable<Hotkey> ApplySorting(
        IQueryable<Hotkey> query, string? sortField, bool descending)
    {
        string field = sortField?.Trim().ToLowerInvariant() ?? "createdat";

        return (field, descending) switch
        {
            ("updatedat", true) => query.OrderByDescending(h => h.UpdatedAt).ThenBy(h => h.Id),
            ("updatedat", false) => query.OrderBy(h => h.UpdatedAt).ThenBy(h => h.Id),
            ("description", true) => query.OrderByDescending(h => h.Description).ThenBy(h => h.Id),
            ("description", false) => query.OrderBy(h => h.Description).ThenBy(h => h.Id),
            ("key", true) => query.OrderByDescending(h => h.Key).ThenBy(h => h.Id),
            ("key", false) => query.OrderBy(h => h.Key).ThenBy(h => h.Id),
            ("ctrl", true) => query.OrderByDescending(h => h.Ctrl).ThenBy(h => h.Id),
            ("ctrl", false) => query.OrderBy(h => h.Ctrl).ThenBy(h => h.Id),
            ("alt", true) => query.OrderByDescending(h => h.Alt).ThenBy(h => h.Id),
            ("alt", false) => query.OrderBy(h => h.Alt).ThenBy(h => h.Id),
            ("shift", true) => query.OrderByDescending(h => h.Shift).ThenBy(h => h.Id),
            ("shift", false) => query.OrderBy(h => h.Shift).ThenBy(h => h.Id),
            ("win", true) => query.OrderByDescending(h => h.Win).ThenBy(h => h.Id),
            ("win", false) => query.OrderBy(h => h.Win).ThenBy(h => h.Id),
            ("action", true) => query.OrderByDescending(h => h.Action).ThenBy(h => h.Id),
            ("action", false) => query.OrderBy(h => h.Action).ThenBy(h => h.Id),
            ("parameters", true) => query.OrderByDescending(h => h.Parameters).ThenBy(h => h.Id),
            ("parameters", false) => query.OrderBy(h => h.Parameters).ThenBy(h => h.Id),
            (_, true) => query.OrderByDescending(h => h.CreatedAt).ThenBy(h => h.Id),
            (_, false) => query.OrderBy(h => h.CreatedAt).ThenBy(h => h.Id),
        };
    }
}
