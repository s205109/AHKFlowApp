using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Common;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using FluentValidation;
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
    IReadOnlyList<Guid>? CategoryIds = null);

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
    ICurrentUser currentUser,
    AppEnvironment env,
    TimeProvider clock)
    : IUseCaseHandler<ListHotkeysQuery, Result<PagedList<HotkeyDto>>>
{
    // Mirrors SeedHotkeysCommand.s_samples — update both if seed set changes.
    private static readonly (
        string Description, bool Ctrl, bool Alt, bool Shift, bool Win,
        string Key, HotkeyAction Action, string Parameters, string[] Categories)[] s_lazySeed =
    [
        ("Launch Windows Terminal", true,  true,  false, false, "T",     HotkeyAction.Run,  "wt.exe",       ["App Launcher"]),
        ("Launch Notepad",          true,  true,  false, false, "N",     HotkeyAction.Run,  "notepad.exe",  ["App Launcher"]),
        ("Launch File Explorer",    true,  true,  false, false, "E",     HotkeyAction.Run,  "explorer.exe", ["App Launcher"]),
        ("Open default browser",    true,  true,  false, false, "B",     HotkeyAction.Run,  "https://",     ["App Launcher"]),
        ("Maximize window",         false, true,  false, true,  "Up",    HotkeyAction.Send, "{Up}",         ["Window Management"]),
        ("Minimize window",         false, true,  false, true,  "Down",  HotkeyAction.Send, "{Down}",       ["Window Management"]),
        ("Snap window left",        false, true,  false, true,  "Left",  HotkeyAction.Send, "{Left}",       ["Window Management"]),
        ("Snap window right",       false, true,  false, true,  "Right", HotkeyAction.Send, "{Right}",      ["Window Management"]),
        ("Paste as plain text",     true,  false, true,  false, "V",     HotkeyAction.Send, "^v",           ["Code"]),
        ("Insert today's date",     true,  true,  false, false, "D",     HotkeyAction.Send, "{{date:yyyy-MM-dd}}", ["DateTime"]),
        ("Lock workstation",        true,  true,  false, false, "L",     HotkeyAction.Run,  "rundll32.exe user32.dll,LockWorkStation", ["App Launcher"]),
        ("Reload AHK script",       true,  true,  false, false, "R",     HotkeyAction.Run,  "Reload",       ["App Launcher"]),
    ];

    public async Task<Result<PagedList<HotkeyDto>>> ExecuteAsync(ListHotkeysQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        await EnsureHotkeysSeededAsync(ownerOid, ct);

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

    private async Task EnsureHotkeysSeededAsync(Guid ownerOid, CancellationToken ct)
    {
        if (!env.IsDevelopment) return;

        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);

        if (pref?.HotkeysSeededAt is not null) return;

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

        foreach ((string descr, bool ctrl, bool alt, bool shift, bool win, string key,
                  HotkeyAction action, string param, string[] cats) in s_lazySeed)
        {
            var hk = Hotkey.Create(ownerOid, descr, key, ctrl, alt, shift, win,
                action, param, appliesToAllProfiles: true, clock);
            db.Hotkeys.Add(hk);
            foreach (string catName in cats)
            {
                if (catByName.TryGetValue(catName, out Guid catId))
                    db.HotkeyCategories.Add(HotkeyCategory.Create(hk.Id, catId));
            }
        }

        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            if (seedingCategories) pref.MarkCategoriesSeeded(clock);
            pref.MarkHotkeysSeeded(clock);
            db.UserPreferences.Add(pref);
        }
        else
        {
            if (seedingCategories) pref.MarkCategoriesSeeded(clock);
            pref.MarkHotkeysSeeded(clock);
        }

        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex) when (ex.IsDuplicateKeyViolation())
        {
            // Concurrent first-call race or pre-existing data after migration (null
            // markers but hotkeys already present) — detach pending entities and
            // persist markers in a follow-up save so future GETs skip the seed path.
            foreach (Hotkey hk in db.Hotkeys.Local.ToList())
                db.Entry(hk).State = EntityState.Detached;
            foreach (HotkeyCategory hc in db.HotkeyCategories.Local.ToList())
                db.Entry(hc).State = EntityState.Detached;
            foreach (Category cat in db.Categories.Local.ToList())
                db.Entry(cat).State = EntityState.Detached;
            if (pref is not null)
                db.Entry(pref).State = EntityState.Detached;

            // Reload pref (may have been inserted by the concurrent winner) and mark only the
            // sets that actually landed. The winner may be the categories seeder
            // (ListCategoriesQuery), which inserts categories and the pref row but never any
            // hotkeys; marking hotkeys seeded here would strand the owner on an empty set that
            // the guard above stops any later request from retrying.
            pref = await db.UserPreferences.FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);
            if (pref is null)
            {
                pref = UserPreference.CreateDefault(ownerOid, clock);
                db.UserPreferences.Add(pref);
            }
            if (pref.CategoriesSeededAt is null && await db.Categories.AnyAsync(c => c.OwnerOid == ownerOid, ct))
                pref.MarkCategoriesSeeded(clock);
            if (pref.HotkeysSeededAt is null && await db.Hotkeys.AnyAsync(h => h.OwnerOid == ownerOid, ct))
                pref.MarkHotkeysSeeded(clock);
            await db.SaveChangesAsync(ct);
        }
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
