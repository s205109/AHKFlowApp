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
    int Page = 1,
    int PageSize = 50,
    string? SortField = null,
    bool SortDescending = true,
    string? TriggerFilter = null,
    string? ReplacementFilter = null,
    string? DescriptionFilter = null,
    bool? AppliesToAllProfiles = null,
    bool? IsEndingCharacterRequired = null,
    bool? IsTriggerInsideWord = null,
    IReadOnlyList<Guid>? CategoryIds = null) : IRequest<Result<PagedList<HotstringDto>>>;

public sealed class ListHotstringsQueryValidator : AbstractValidator<ListHotstringsQuery>
{
    private static readonly string[] AllowedSortFields =
    [
        "createdAt",
        "updatedAt",
        "trigger",
        "replacement",
        "description",
        "isEndingCharacterRequired",
        "isTriggerInsideWord",
    ];

    public ListHotstringsQueryValidator()
    {
        RuleFor(x => x.Search).MaximumLength(200);
        RuleFor(x => x.TriggerFilter).MaximumLength(200);
        RuleFor(x => x.ReplacementFilter).MaximumLength(200);
        RuleFor(x => x.DescriptionFilter).MaximumLength(200);
        RuleFor(x => x.Page).InclusiveBetween(1, 10_000);
        RuleFor(x => x.PageSize).InclusiveBetween(1, 200);
        RuleFor(x => x.SortField)
            .Must(field => string.IsNullOrWhiteSpace(field) || AllowedSortFields.Contains(field, StringComparer.OrdinalIgnoreCase))
            .WithMessage($"SortField must be one of: {string.Join(", ", AllowedSortFields)}.");
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

        // Case-insensitive: relies on the database collation (SQL_Latin1_General_CP1_CI_AS).
        // Do not add an ignoreCase parameter — see docs/architecture/search-semantics.md.
        if (!string.IsNullOrWhiteSpace(request.Search))
        {
            string pattern = $"%{request.Search.Trim()}%";
            query = query.Where(h =>
                EF.Functions.Like(h.Trigger, pattern) ||
                EF.Functions.Like(h.Replacement, pattern) ||
                (h.Description != null && EF.Functions.Like(h.Description, pattern)));
        }

        if (!string.IsNullOrWhiteSpace(request.TriggerFilter))
        {
            string pattern = $"%{request.TriggerFilter.Trim()}%";
            query = query.Where(h => EF.Functions.Like(h.Trigger, pattern));
        }

        if (!string.IsNullOrWhiteSpace(request.ReplacementFilter))
        {
            string pattern = $"%{request.ReplacementFilter.Trim()}%";
            query = query.Where(h => EF.Functions.Like(h.Replacement, pattern));
        }

        if (!string.IsNullOrWhiteSpace(request.DescriptionFilter))
        {
            string pattern = $"%{request.DescriptionFilter.Trim()}%";
            query = query.Where(h => h.Description != null && EF.Functions.Like(h.Description, pattern));
        }

        if (request.AppliesToAllProfiles is { } appliesToAllProfiles)
            query = query.Where(h => h.AppliesToAllProfiles == appliesToAllProfiles);

        if (request.IsEndingCharacterRequired is { } isEndingCharacterRequired)
            query = query.Where(h => h.IsEndingCharacterRequired == isEndingCharacterRequired);

        if (request.IsTriggerInsideWord is { } isTriggerInsideWord)
            query = query.Where(h => h.IsTriggerInsideWord == isTriggerInsideWord);

        if (request.CategoryIds is { Count: > 0 })
        {
            Guid[] ids = request.CategoryIds.Distinct().ToArray();
            query = query.Where(h => h.Categories.Any(hc => ids.Contains(hc.CategoryId)));
        }

        int total = await query.CountAsync(ct);

        List<HotstringDto> items = await ApplySorting(query, request.SortField, request.SortDescending)
            .Skip((request.Page - 1) * request.PageSize)
            .Take(request.PageSize)
            .Select(h => new HotstringDto(
                h.Id,
                h.Profiles.Select(p => p.ProfileId).ToArray(),
                h.AppliesToAllProfiles,
                h.Trigger,
                h.Replacement,
                h.Description,
                h.IsEndingCharacterRequired,
                h.IsTriggerInsideWord,
                h.CreatedAt,
                h.UpdatedAt,
                h.Categories.Select(hc => hc.CategoryId).ToArray()))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotstringDto>(items, request.Page, request.PageSize, total));
    }

    private static IOrderedQueryable<Hotstring> ApplySorting(
        IQueryable<Hotstring> query,
        string? sortField,
        bool descending)
    {
        string normalized = sortField?.Trim().ToLowerInvariant() ?? "createdat";

        IOrderedQueryable<Hotstring> ordered = normalized switch
        {
            "trigger" => descending ? query.OrderByDescending(h => h.Trigger) : query.OrderBy(h => h.Trigger),
            "replacement" => descending ? query.OrderByDescending(h => h.Replacement) : query.OrderBy(h => h.Replacement),
            "description" => descending ? query.OrderByDescending(h => h.Description) : query.OrderBy(h => h.Description),
            "isendingcharacterrequired" => descending ? query.OrderByDescending(h => h.IsEndingCharacterRequired) : query.OrderBy(h => h.IsEndingCharacterRequired),
            "istriggerinsideword" => descending ? query.OrderByDescending(h => h.IsTriggerInsideWord) : query.OrderBy(h => h.IsTriggerInsideWord),
            "updatedat" => descending ? query.OrderByDescending(h => h.UpdatedAt) : query.OrderBy(h => h.UpdatedAt),
            _ => descending ? query.OrderByDescending(h => h.CreatedAt) : query.OrderBy(h => h.CreatedAt),
        };

        return ordered.ThenBy(h => h.Id);
    }
}
