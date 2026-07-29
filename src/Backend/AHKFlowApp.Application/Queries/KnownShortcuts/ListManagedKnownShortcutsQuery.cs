using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.KnownShortcuts;

/// <summary>Every known shortcut for the management page, ignored uses included so they can be brought back.</summary>
public sealed record ListManagedKnownShortcutsQuery();

internal sealed class ListManagedKnownShortcutsQueryHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<ListManagedKnownShortcutsQuery, Result<ManagedKnownShortcutCatalogDto>>
{
    public async Task<Result<ManagedKnownShortcutCatalogDto>> ExecuteAsync(
        ListManagedKnownShortcutsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        (CustomKnownShortcut[] owned, IgnoredKnownShortcut[] ignored) =
            await OwnerKnownShortcutLoader.LoadAsync(db, ownerOid, ct);

        return Result<ManagedKnownShortcutCatalogDto>.Success(
            new ManagedKnownShortcutCatalogDto(KnownShortcutMerge.ForManagement(owned, ignored)));
    }
}
