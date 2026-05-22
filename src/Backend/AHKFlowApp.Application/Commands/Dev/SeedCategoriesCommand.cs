using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: seeds the eight starter categories for the current user.
// Idempotent on (OwnerOid, Name). Also sets UserPreference.CategoriesSeededAt
// so a subsequent GET /categories does not lazy-seed again.
public sealed record SeedCategoriesCommand(bool Reset) : IRequest<Result<IReadOnlyList<CategoryDto>>>;

internal sealed class SeedCategoriesCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IRequestHandler<SeedCategoriesCommand, Result<IReadOnlyList<CategoryDto>>>
{
    public static readonly string[] DefaultNames =
    [
        "Autocorrect", "Communication", "DateTime", "Email",
        "Code", "Symbols", "Window Management", "App Launcher",
    ];

    public async Task<Result<IReadOnlyList<CategoryDto>>> Handle(SeedCategoriesCommand request, CancellationToken ct)
    {
        if (!env.IsDevelopment)
            return Result.NotFound();

        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        if (request.Reset)
        {
            List<Category> existing = await db.Categories
                .Where(c => c.OwnerOid == ownerOid)
                .ToListAsync(ct);
            db.Categories.RemoveRange(existing);
        }

        // After RemoveRange the rows still exist in the DB until SaveChanges, so a
        // per-name query would wrongly report them as present. On reset, treat the
        // owner's category set as empty and insert the full default list fresh.
        HashSet<string> existingNames = request.Reset
            ? new(StringComparer.OrdinalIgnoreCase)
            : (await db.Categories
                    .Where(c => c.OwnerOid == ownerOid)
                    .Select(c => c.Name)
                    .ToListAsync(ct))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (string name in DefaultNames)
        {
            if (!existingNames.Add(name)) continue;
            db.Categories.Add(Category.Create(ownerOid, name, clock));
        }

        // Upsert the seed marker so a later GET /categories does not also lazy-seed.
        UserPreference? pref = await db.UserPreferences
            .FirstOrDefaultAsync(p => p.OwnerOid == ownerOid, ct);
        if (pref is null)
        {
            pref = UserPreference.CreateDefault(ownerOid, clock);
            db.UserPreferences.Add(pref);
        }
        if (request.Reset)
        {
            // MarkCategoriesSeeded is a no-op when already set; clear it so reset
            // refreshes the marker to the current clock tick.
            db.Entry(pref).Property(p => p.CategoriesSeededAt).CurrentValue = null;
        }
        pref.MarkCategoriesSeeded(clock);

        await db.SaveChangesAsync(ct);

        List<CategoryDto> items = await db.Categories
            .AsNoTracking()
            .Where(c => c.OwnerOid == ownerOid)
            .OrderBy(c => c.Name)
            .Select(c => new CategoryDto(c.Id, c.Name, c.CreatedAt, c.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success<IReadOnlyList<CategoryDto>>(items);
    }
}
