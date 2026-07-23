using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: seeds curated sample hotkeys for the current user, each linked to
// one or more categories. Idempotent on (OwnerOid, Key, Ctrl, Alt, Shift, Win);
// a non-reset re-run backfills missing category links onto pre-existing rows.
public sealed record SeedHotkeysCommand(bool Reset);

internal sealed class SeedHotkeysCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IUseCaseHandler<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>>
{
    public async Task<Result<PagedList<HotkeyDto>>> ExecuteAsync(SeedHotkeysCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        if (request.Reset)
        {
            List<Hotkey> existing = await db.Hotkeys
                .Where(h => h.OwnerOid == ownerOid)
                .ToListAsync(ct);
            db.Hotkeys.RemoveRange(existing);
        }

        var catByName = (await db.Categories
                .Where(c => c.OwnerOid == ownerOid)
                .Select(c => new { c.Name, c.Id })
                .ToListAsync(ct))
            .ToDictionary(c => c.Name, c => c.Id, StringComparer.OrdinalIgnoreCase);

        // On reset the prior hotkeys/junctions still exist in the DB until
        // SaveChanges (junctions cascade-delete with their hotkeys), so treat the
        // link set as empty and skip the per-key existence lookup.
        HashSet<(Guid HotkeyId, Guid CategoryId)> existingLinks = request.Reset
            ? []
            : (await db.HotkeyCategories
                    .Where(hc => hc.Hotkey.OwnerOid == ownerOid)
                    .Select(hc => new { hc.HotkeyId, hc.CategoryId })
                    .ToListAsync(ct))
                .Select(x => (x.HotkeyId, x.CategoryId))
                .ToHashSet();

        foreach (DefaultHotkey sample in DefaultHotkeyCatalog.All)
        {
            // Copied into locals so the identity lookup below closes over plain values.
            string key = sample.Key;
            bool ctrl = sample.Ctrl;
            bool alt = sample.Alt;
            bool shift = sample.Shift;
            bool win = sample.Win;

            Hotkey? existing = request.Reset
                ? null
                : await db.Hotkeys.FirstOrDefaultAsync(h =>
                    h.OwnerOid == ownerOid &&
                    h.Key == key &&
                    h.Ctrl == ctrl && h.Alt == alt && h.Shift == shift && h.Win == win, ct);

            Guid hotkeyId;
            if (existing is not null)
            {
                hotkeyId = existing.Id;
            }
            else
            {
                var entity = Hotkey.Create(
                    ownerOid,
                    LegacyHotkeyDefinitionConverter.FromLegacy(
                        description: sample.Description, key: key,
                        ctrl: ctrl, alt: alt, shift: shift, win: win,
                        action: sample.Action, parameters: sample.Parameters,
                        appliesToAllProfiles: true),
                    clock);
                db.Hotkeys.Add(entity);
                hotkeyId = entity.Id;
            }

            foreach (string cat in sample.Categories)
            {
                if (!catByName.TryGetValue(cat, out Guid cid)) continue;
                if (!existingLinks.Add((hotkeyId, cid))) continue;
                db.HotkeyCategories.Add(HotkeyCategory.Create(hotkeyId, cid));
            }
        }

        // Upsert the seed marker so a later GET /hotkeys does not also lazy-seed.
        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);
        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            db.UserPreferences.Add(pref);
        }
        if (request.Reset)
        {
            // MarkHotkeysSeeded is a no-op when already set; clear it so reset
            // refreshes the marker to the current clock tick.
            db.Entry(pref).Property(p => p.HotkeysSeededAt).CurrentValue = null;
        }
        pref.MarkHotkeysSeeded(clock);

        await db.SaveChangesAsync(ct);

        List<HotkeyDto> items = await db.Hotkeys
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .OrderBy(h => h.Description)
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
                h.ActionKind,
                h.Text,
                h.SendKeysContent,
                h.RunTarget,
                h.RunTargetKind,
                h.WindowOp,
                h.RemapDest,
                h.Body,
                h.CreatedAt,
                h.UpdatedAt,
                h.Categories.Select(hc => hc.CategoryId).ToArray()))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotkeyDto>(items, Page: 1, PageSize: items.Count, TotalCount: items.Count));
    }
}
