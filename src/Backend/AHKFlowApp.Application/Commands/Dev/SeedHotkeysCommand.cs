using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: seeds curated sample hotkeys for the current user, each linked to
// one or more categories. Idempotent on (OwnerOid, Key, Ctrl, Alt, Shift, Win);
// a non-reset re-run backfills missing category links onto pre-existing rows.
public sealed record SeedHotkeysCommand(bool Reset) : IRequest<Result<PagedList<HotkeyDto>>>;

internal sealed class SeedHotkeysCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IRequestHandler<SeedHotkeysCommand, Result<PagedList<HotkeyDto>>>
{
    private static readonly (
        string Description,
        bool Ctrl, bool Alt, bool Shift, bool Win,
        string Key,
        HotkeyAction Action,
        string Parameters,
        string[] Categories)[] s_samples =
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

    public async Task<Result<PagedList<HotkeyDto>>> Handle(SeedHotkeysCommand request, CancellationToken ct)
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

        foreach ((string descr, bool ctrl, bool alt, bool shift, bool win, string key, HotkeyAction action, string param, string[] cats) in s_samples)
        {
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
                    ownerOid, descr, key, ctrl, alt, shift, win, action, param,
                    appliesToAllProfiles: true, clock);
                db.Hotkeys.Add(entity);
                hotkeyId = entity.Id;
            }

            foreach (string cat in cats)
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
                h.Action,
                h.Parameters,
                h.CreatedAt,
                h.UpdatedAt,
                h.Categories.Select(hc => hc.CategoryId).ToArray()))
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotkeyDto>(items, Page: 1, PageSize: items.Count, TotalCount: items.Count));
    }
}
