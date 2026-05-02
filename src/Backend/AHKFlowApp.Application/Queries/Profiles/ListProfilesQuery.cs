using System.Diagnostics.CodeAnalysis;
using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Mapping;
using AHKFlowApp.Domain.Constants;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;
using MediatR;
using Microsoft.EntityFrameworkCore;

namespace AHKFlowApp.Application.Queries.Profiles;

public sealed record ListProfilesQuery : IRequest<Result<IReadOnlyList<ProfileDto>>>;

internal sealed class ListProfilesQueryHandler(
    IAppDbContext db,
    ICurrentUser currentUser,
    TimeProvider clock)
    : IRequestHandler<ListProfilesQuery, Result<IReadOnlyList<ProfileDto>>>
{
    public async Task<Result<IReadOnlyList<ProfileDto>>> Handle(ListProfilesQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        bool any = await db.Profiles.AnyAsync(p => p.OwnerOid == ownerOid, ct);
        if (!any)
        {
            var seeded = Profile.Create(
                ownerOid,
                name: "Default",
                isDefault: true,
                headerTemplate: DefaultProfileTemplates.Header,
                footerTemplate: DefaultProfileTemplates.Footer,
                clock: clock);
            db.Profiles.Add(seeded);
            try
            {
                await db.SaveChangesAsync(ct);
            }
            catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
            {
                // Concurrent first-time list: another request already seeded the default profile.
                // Fall through to the read query below; no further SaveChanges occurs in this handler.
            }
        }

        List<ProfileDto> items = await db.Profiles
            .AsNoTracking()
            .Where(p => p.OwnerOid == ownerOid)
            .OrderByDescending(p => p.IsDefault)
            .ThenBy(p => p.Name)
            .Select(p => new ProfileDto(
                p.Id, p.Name, p.IsDefault, p.HeaderTemplate, p.FooterTemplate, p.CreatedAt, p.UpdatedAt))
            .ToListAsync(ct);

        return Result.Success<IReadOnlyList<ProfileDto>>(items);
    }

    // Checks SQL Server unique-constraint error codes (2601/2627) without importing Microsoft.Data.SqlClient,
    // which would couple the Application layer to an infrastructure concern.
    [ExcludeFromCodeCoverage]
    private static bool IsDuplicateKeyViolation(DbUpdateException ex) =>
        ex.InnerException?.GetType().GetProperty("Number")?.GetValue(ex.InnerException) is int n &&
        n is 2601 or 2627;
}
