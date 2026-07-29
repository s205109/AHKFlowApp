using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Hotkeys;

/// <summary>Known shortcuts the dialog should warn about — built-ins the owner has not silenced, plus their own records.</summary>
public sealed record ListKnownShortcutsQuery();

internal sealed class ListKnownShortcutsQueryHandler(IAppDbContext db, ICurrentUser currentUser)
    : IUseCaseHandler<ListKnownShortcutsQuery, Result<KnownShortcutCatalogDto>>
{
    public async Task<Result<KnownShortcutCatalogDto>> ExecuteAsync(
        ListKnownShortcutsQuery request, CancellationToken ct)
    {
        if (currentUser.Oid is not Guid ownerOid)
            return Result.Unauthorized();

        (CustomKnownShortcut[] owned, IgnoredKnownShortcut[] ignored) =
            await OwnerKnownShortcutLoader.LoadAsync(db, ownerOid, ct);

        return Result<KnownShortcutCatalogDto>.Success(
            new KnownShortcutCatalogDto(KnownShortcutMerge.ForDialog(owned, ignored)));
    }
}
