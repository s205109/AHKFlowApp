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
    IDevEnvironment env)
    : IRequestHandler<SeedHotstringsCommand, Result<PagedList<HotstringDto>>>
{
    private static readonly (string Trigger, string Replacement, bool Ending, bool InsideWord)[] Samples =
    [
        ("btw",    "by the way",            true,  true),
        ("fyi",    "for your information",  true,  true),
        ("omw",    "on my way",             true,  true),
        ("ty",     "thank you",             true,  true),
        ("afaik",  "as far as I know",      true,  true),
        ("idk",    "I don't know",          true,  true),
        ("brb",    "be right back",         true,  true),
        ("asap",   "as soon as possible",   true,  true),
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

        foreach ((string trigger, string replacement, bool ending, bool inside) in Samples)
        {
            bool exists = await db.Hotstrings.AnyAsync(
                h => h.OwnerOid == ownerOid
                  && h.ProfileId == null
                  && h.Trigger == trigger,
                ct);

            if (exists) continue;

            db.Hotstrings.Add(Hotstring.Create(
                ownerOid, trigger, replacement, profileId: null,
                isEndingCharacterRequired: ending, isTriggerInsideWord: inside, clock));
        }

        await db.SaveChangesAsync(ct);

        List<HotstringDto> items = await db.Hotstrings
            .AsNoTracking()
            .Where(h => h.OwnerOid == ownerOid)
            .OrderByDescending(h => h.CreatedAt)
            .Select(h => h.ToDto())
            .ToListAsync(ct);

        return Result.Success(new PagedList<HotstringDto>(items, Page: 1, PageSize: items.Count, TotalCount: items.Count));
    }
}
