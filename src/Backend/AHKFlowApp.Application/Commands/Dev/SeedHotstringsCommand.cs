using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Commands.Dev;

// Dev-only: seeds curated sample hotstrings for the current user.
public sealed record SeedHotstringsCommand(bool Reset) : IRequest<Result<PagedList<HotstringDto>>>;

internal sealed class SeedHotstringsCommandHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock,
    AppEnvironment env)
    : IRequestHandler<SeedHotstringsCommand, Result<PagedList<HotstringDto>>>
{
    private static readonly (string Trigger, string Replacement, bool Ending, bool InsideWord)[] s_samples =
    [
        ("btw", "by the way",           true, true),
        ("fyi", "for your information", true, true),
        ("brb", "be right back",        true, true),
    ];

    public async Task<Result<PagedList<HotstringDto>>> Handle(SeedHotstringsCommand request, CancellationToken ct)
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

        foreach ((string trigger, string replacement, bool ending, bool inside) in s_samples)
        {
            bool exists = await db.Hotstrings.AnyAsync(
                h => h.OwnerOid == ownerOid && h.Trigger == trigger,
                ct);

            if (exists) continue;

            db.Hotstrings.Add(Hotstring.Create(
                ownerOid, trigger, replacement, appliesToAllProfiles: true,
                isEndingCharacterRequired: ending, isTriggerInsideWord: inside, clock));
        }

        await db.SaveChangesAsync(ct);

        List<HotstringDto> items = await db.Hotstrings
            .AsNoTracking()
            .Include(h => h.Profiles)
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.CreatedAt)
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

        return Result.Success(new PagedList<HotstringDto>(items, Page: 1, PageSize: items.Count, TotalCount: items.Count));
    }
}
