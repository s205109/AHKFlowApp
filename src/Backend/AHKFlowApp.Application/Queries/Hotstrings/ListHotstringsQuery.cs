using System.Linq.Expressions;
using System.Reflection;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Commands.Dev;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;
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
    IReadOnlyList<Guid>? CategoryIds = null,
    HotstringKind? Kind = null);

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
        "kind",
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
    ICurrentUser currentUser,
    AppEnvironment env,
    TimeProvider clock)
    : IUseCaseHandler<ListHotstringsQuery, Result<PagedList<HotstringDto>>>
{
    internal const int ListReplacementPreviewLength = 200;

    // Shared, EF-translatable "searchable replacement" selector: DateTime-kind hotstrings store
    // Replacement = "" and carry their format string in DateTimeFormat instead. Search/filter/sort
    // on the replacement column must fall back to DateTimeFormat for those rows. Defined once here
    // and reused for the global Search clause, ReplacementFilter, and the "replacement" sort case.
    private static readonly Expression<Func<Hotstring, string>> SearchableReplacementSelector =
        h => h.Kind == HotstringKind.DateTime ? (h.DateTimeFormat ?? "") : h.Replacement;

    private static readonly MethodInfo LikeMethod = typeof(DbFunctionsExtensions).GetMethod(
        nameof(DbFunctionsExtensions.Like),
        [typeof(DbFunctions), typeof(string), typeof(string)])!;

    /// <summary>Builds <c>h => EF.Functions.Like(SearchableReplacementSelector-body, pattern)</c>,
    /// reusing <see cref="SearchableReplacementSelector"/>'s body and parameter directly.</summary>
    private static Expression<Func<Hotstring, bool>> SearchableReplacementLike(string pattern)
    {
        MethodCallExpression call = Expression.Call(
            LikeMethod,
            Expression.Property(null, typeof(EF), nameof(EF.Functions)),
            SearchableReplacementSelector.Body,
            Expression.Constant(pattern));

        return Expression.Lambda<Func<Hotstring, bool>>(call, SearchableReplacementSelector.Parameters[0]);
    }

    /// <summary>Combines two <see cref="Hotstring"/> predicates with OR, rebinding <paramref name="right"/>
    /// onto <paramref name="left"/>'s parameter so the result is a single valid expression tree.</summary>
    private static Expression<Func<Hotstring, bool>> Or(
        Expression<Func<Hotstring, bool>> left,
        Expression<Func<Hotstring, bool>> right)
    {
        Expression rightBody = new ParameterRebinder(right.Parameters[0], left.Parameters[0]).Visit(right.Body)!;
        return Expression.Lambda<Func<Hotstring, bool>>(Expression.OrElse(left.Body, rightBody), left.Parameters[0]);
    }

    private sealed class ParameterRebinder(ParameterExpression from, ParameterExpression to) : ExpressionVisitor
    {
        protected override Expression VisitParameter(ParameterExpression node) => node == from ? to : base.VisitParameter(node);
    }

    public async Task<Result<PagedList<HotstringDto>>> ExecuteAsync(ListHotstringsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        await EnsureHotstringsSeededAsync(ownerOid, ct);

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
            Expression<Func<Hotstring, bool>> triggerLike = h => EF.Functions.Like(h.Trigger, pattern);
            Expression<Func<Hotstring, bool>> replacementLike = SearchableReplacementLike(pattern);
            Expression<Func<Hotstring, bool>> descriptionLike = h => h.Description != null && EF.Functions.Like(h.Description, pattern);
            query = query.Where(Or(Or(triggerLike, replacementLike), descriptionLike));
        }

        if (!string.IsNullOrWhiteSpace(request.TriggerFilter))
        {
            string pattern = $"%{request.TriggerFilter.Trim()}%";
            query = query.Where(h => EF.Functions.Like(h.Trigger, pattern));
        }

        if (!string.IsNullOrWhiteSpace(request.ReplacementFilter))
        {
            string pattern = $"%{request.ReplacementFilter.Trim()}%";
            query = query.Where(SearchableReplacementLike(pattern));
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

        if (request.Kind.HasValue)
            query = query.Where(h => h.Kind == request.Kind.Value);

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
                // Trailing spaces matter here: string.Length translates to SQL Server LEN(), which
                // strips them, so it would disagree with the DATALENGTH-based EffectiveDelivery
                // below on space-padded replacements. Use the same DATALENGTH/2 char count for both.
                h.Kind == HotstringKind.Text
                    && (EF.Functions.DataLength(h.Replacement) ?? 0) / 2 > ListReplacementPreviewLength
                    ? h.Replacement.Substring(0, ListReplacementPreviewLength)
                    : h.Replacement,
                h.Description,
                h.IsEndingCharacterRequired,
                h.IsTriggerInsideWord,
                h.CreatedAt,
                h.UpdatedAt,
                h.Categories.Select(hc => hc.CategoryId).ToArray(),
                h.Kind,
                h.IsCaseSensitive,
                h.OmitEndingCharacter,
                h.DateTimeFormat,
                h.DateOffsetAmount,
                h.DateOffsetUnit,
                h.ContextMatchType,
                h.ContextValue,
                h.Delivery,
                // Same DATALENGTH/2 char count as the Replacement projection above — the flag must
                // report exactly when that projection truncated.
                h.Kind == HotstringKind.Text
                    && (EF.Functions.DataLength(h.Replacement) ?? 0) / 2 > ListReplacementPreviewLength,
                // Mirrors HotstringEmitter.ResolveEffectiveDelivery — keep in sync; that resolver
                // can't translate to SQL, so the equivalent expression is inlined here. Replacement
                // is nvarchar(max); string.Length here translates to SQL Server LEN(), which strips
                // trailing spaces and would undercount them against the resolver's .NET Length. Use
                // DATALENGTH (byte count) / 2 (UTF-16 chars) instead, which preserves them.
                h.Kind == HotstringKind.Text
                    && (h.Delivery == HotstringDelivery.ClipboardPaste
                        || (h.Delivery == HotstringDelivery.Auto
                            && (EF.Functions.DataLength(h.Replacement) ?? 0) / 2 >= HotstringDeliveryDefaults.AutoClipboardThresholdChars))
                    ? HotstringDelivery.ClipboardPaste
                    : HotstringDelivery.Type))
            .ToListAsync(ct);

        // SQL SUBSTRING cuts at a UTF-16 code-unit boundary, so a preview ending exactly on the
        // high surrogate of a supplementary character (emoji, etc.) keeps a lone surrogate that
        // renders as a broken glyph. Not expressible in the projection above; drop it here.
        for (int i = 0; i < items.Count; i++)
        {
            HotstringDto item = items[i];
            if (item is { ReplacementIsTruncated: true, Replacement.Length: > 0 }
                && char.IsHighSurrogate(item.Replacement[^1]))
            {
                items[i] = item with { Replacement = item.Replacement[..^1] };
            }
        }

        return Result.Success(new PagedList<HotstringDto>(items, request.Page, request.PageSize, total));
    }

    private async Task EnsureHotstringsSeededAsync(Guid ownerOid, CancellationToken ct)
    {
        if (!env.IsDevelopment) return;

        const int maxAttempts = 2;

        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
            UserPreference? pref = await db.UserPreferences
                .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);

            if (pref?.HotstringsSeededAt is not null) return;

            // Ensure categories exist; seed them inline if this is the user's first request
            bool seedingCategories = pref?.CategoriesSeededAt is null;
            Dictionary<string, Guid> catByName;

            if (seedingCategories)
            {
                catByName = [];
                foreach (string name in DefaultCategories.Names)
                {
                    var cat = Category.Create(ownerOid, name, clock);
                    db.Categories.Add(cat);
                    catByName[name] = cat.Id;
                }
            }
            else
            {
                catByName = (await db.Categories
                        .Where(c => c.OwnerOid == ownerOid)
                        .Select(c => new { c.Name, c.Id })
                        .ToListAsync(ct))
                    .ToDictionary(c => c.Name, c => c.Id, StringComparer.OrdinalIgnoreCase);
            }

            foreach (HotstringSeedSamples.Sample sample in HotstringSeedSamples.All)
            {
                var hs = Hotstring.Create(
                    ownerOid,
                    new HotstringDefinition(
                        sample.Trigger, sample.Replacement, sample.Description,
                        AppliesToAllProfiles: true, sample.Ending, sample.InsideWord,
                        Kind: sample.Kind, DateTimeFormat: sample.DateTimeFormat),
                    clock);
                db.Hotstrings.Add(hs);
                foreach (string catName in sample.Categories)
                {
                    if (catByName.TryGetValue(catName, out Guid catId))
                        db.HotstringCategories.Add(HotstringCategory.Create(hs.Id, catId));
                }
            }

            if (pref is null)
            {
                pref = UserPreference.CreateDefault(ownerOid, clock);
                if (seedingCategories) pref.MarkCategoriesSeeded(clock);
                pref.MarkHotstringsSeeded(clock);
                db.UserPreferences.Add(pref);
            }
            else
            {
                if (seedingCategories) pref.MarkCategoriesSeeded(clock);
                pref.MarkHotstringsSeeded(clock);
            }

            try
            {
                await db.SaveChangesAsync(ct);
                return;
            }
            catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
            {
                // Concurrent first-call race or pre-existing data after migration (null
                // markers but hotstrings already present) — detach pending entities, then
                // persist only markers backed by rows that actually committed.
                foreach (Hotstring hs in db.Hotstrings.Local.ToList())
                    db.Entry(hs).State = EntityState.Detached;
                foreach (HotstringCategory hc in db.HotstringCategories.Local.ToList())
                    db.Entry(hc).State = EntityState.Detached;
                foreach (Category cat in db.Categories.Local.ToList())
                    db.Entry(cat).State = EntityState.Detached;
                if (pref is not null)
                    db.Entry(pref).State = EntityState.Detached;

                // The winner may be ListCategoriesQuery, which inserts categories and the pref
                // row but no hotstrings. In that case, persist the truthful category marker and
                // retry once so this request can insert the hotstrings against those categories.
                pref = await db.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);
                if (pref is null)
                {
                    pref = UserPreference.CreateDefault(ownerOid, clock);
                    db.UserPreferences.Add(pref);
                }

                bool categoriesExist = await db.Categories.AnyAsync(c => c.OwnerOid == ownerOid, ct);
                bool hotstringsExist = await db.Hotstrings.AnyAsync(h => h.OwnerOid == ownerOid, ct);

                if (pref.CategoriesSeededAt is null && categoriesExist)
                    pref.MarkCategoriesSeeded(clock);
                if (pref.HotstringsSeededAt is null && hotstringsExist)
                    pref.MarkHotstringsSeeded(clock);
                await db.SaveChangesAsync(ct);

                if (hotstringsExist || attempt == maxAttempts)
                    return;
            }
        }
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
            "replacement" => descending ? query.OrderByDescending(SearchableReplacementSelector) : query.OrderBy(SearchableReplacementSelector),
            "description" => descending ? query.OrderByDescending(h => h.Description) : query.OrderBy(h => h.Description),
            "isendingcharacterrequired" => descending ? query.OrderByDescending(h => h.IsEndingCharacterRequired) : query.OrderBy(h => h.IsEndingCharacterRequired),
            "istriggerinsideword" => descending ? query.OrderByDescending(h => h.IsTriggerInsideWord) : query.OrderBy(h => h.IsTriggerInsideWord),
            "updatedat" => descending ? query.OrderByDescending(h => h.UpdatedAt) : query.OrderBy(h => h.UpdatedAt),
            "kind" => descending ? query.OrderByDescending(h => h.Kind) : query.OrderBy(h => h.Kind),
            _ => descending ? query.OrderByDescending(h => h.CreatedAt) : query.OrderBy(h => h.CreatedAt),
        };

        return ordered.ThenBy(h => h.Id);
    }
}
