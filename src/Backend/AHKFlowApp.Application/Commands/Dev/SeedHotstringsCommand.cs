using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: seeds curated sample hotstrings for the current user, each linked
// to one or more categories. Idempotent on (OwnerOid, Trigger); a non-reset
// re-run backfills missing category links onto pre-existing seed rows.
public sealed record SeedHotstringsCommand(bool Reset);

internal sealed class SeedHotstringsCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IUseCaseHandler<SeedHotstringsCommand, Result<PagedList<HotstringDto>>>
{
    private static readonly (
        string Trigger,
        string Replacement,
        bool Ending,
        bool InsideWord,
        string[] Categories,
        HotstringKind Kind,
        string? DateTimeFormat)[] s_samples =
    [
        ("recieve", "receive",              true,  true,  ["Autocorrect"],  HotstringKind.Text,     null),
        ("btw",     "by the way",           true,  false, ["Communication"], HotstringKind.Text,    null),
        ("brb",     "be right back",        true,  false, ["Communication"], HotstringKind.Text,    null),
        ("fyi",     "for your information", true,  false, ["Communication"], HotstringKind.Text,    null),
        ("/today",  "",                     false, false, ["DateTime"],     HotstringKind.DateTime, "yyyy-MM-dd"),
        ("/now",    "",                     false, false, ["DateTime"],     HotstringKind.DateTime, "HH:mm"),
        ("@sig",    "Example User\nuser@example.com\nExample Company", false, false, ["Email"], HotstringKind.Text, null),
        (";arrow",  "→",               false, false, ["Symbols"], HotstringKind.Text, null),
        (";check",  "✓",               false, false, ["Symbols"], HotstringKind.Text, null),
        (";shrug",  "¯\\_(ツ)_/¯", false, false, ["Symbols"], HotstringKind.Text, null),
        (";e:",     "ë",               false, false, ["Symbols"], HotstringKind.Text, null),
        (";todo",   "TODO(name): ",         false, false, ["Code"], HotstringKind.Text, null),
    ];

    public async Task<Result<PagedList<HotstringDto>>> ExecuteAsync(SeedHotstringsCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        if (request.Reset)
        {
            List<Hotstring> existing = await db.Hotstrings
                .Where(h => h.OwnerOid == ownerOid)
                .ToListAsync(ct);
            db.Hotstrings.RemoveRange(existing);
        }

        var categoryByName = (await db.Categories
                .Where(c => c.OwnerOid == ownerOid)
                .Select(c => new { c.Name, c.Id })
                .ToListAsync(ct))
            .ToDictionary(c => c.Name, c => c.Id, StringComparer.OrdinalIgnoreCase);

        // On reset the prior hotstrings/junctions still exist in the DB until
        // SaveChanges (junctions cascade-delete with their hotstrings), so treat
        // the link set as empty and skip the per-trigger existence lookup.
        HashSet<(Guid HotstringId, Guid CategoryId)> existingLinks = request.Reset
            ? []
            : (await db.HotstringCategories
                    .Where(hc => hc.Hotstring.OwnerOid == ownerOid)
                    .Select(hc => new { hc.HotstringId, hc.CategoryId })
                    .ToListAsync(ct))
                .Select(x => (x.HotstringId, x.CategoryId))
                .ToHashSet();

        foreach ((string trigger, string replacement, bool ending, bool inside, string[] cats, HotstringKind kind, string? dateTimeFormat) in s_samples)
        {
            Hotstring? existing = request.Reset
                ? null
                : await db.Hotstrings.FirstOrDefaultAsync(
                    h => h.OwnerOid == ownerOid && h.Trigger == trigger, ct);

            Guid hotstringId;
            if (existing is not null)
            {
                hotstringId = existing.Id;
            }
            else
            {
                var entity = Hotstring.Create(
                    ownerOid,
                    new HotstringDefinition(
                        trigger, replacement, Description: null, AppliesToAllProfiles: true,
                        IsEndingCharacterRequired: ending, IsTriggerInsideWord: inside,
                        Kind: kind, DateTimeFormat: dateTimeFormat),
                    clock);
                db.Hotstrings.Add(entity);
                hotstringId = entity.Id;
            }

            foreach (string categoryName in cats)
            {
                if (!categoryByName.TryGetValue(categoryName, out Guid categoryId)) continue;
                if (!existingLinks.Add((hotstringId, categoryId))) continue;
                db.HotstringCategories.Add(HotstringCategory.Create(hotstringId, categoryId));
            }
        }

        // Upsert the seed marker so a later GET /hotstrings does not also lazy-seed.
        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);
        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            db.UserPreferences.Add(pref);
        }
        if (request.Reset)
        {
            // MarkHotstringsSeeded is a no-op when already set; clear it so reset
            // refreshes the marker to the current clock tick.
            db.Entry(pref).Property(p => p.HotstringsSeededAt).CurrentValue = null;
        }
        pref.MarkHotstringsSeeded(clock);

        await db.SaveChangesAsync(ct);

        List<Hotstring> seeded = await db.Hotstrings
            .AsNoTracking()
            .Include(h => h.Profiles)
            .Include(h => h.Categories)
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.CreatedAt)
            .ToListAsync(ct);

        // Materialize then map via the canonical HotstringMappings.ToDto() so EffectiveDelivery
        // resolves through HotstringEmitter.ResolveEffectiveDelivery instead of defaulting to Type.
        var items = seeded.Select(h => h.ToDto()).ToList();

        return Result.Success(new PagedList<HotstringDto>(items, Page: 1, PageSize: items.Count, TotalCount: items.Count));
    }
}
