using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Hotkeys;

/// <summary>Returns the curated known-shortcut list the hotkey dialog warns from. Static reference data.</summary>
public sealed record ListKnownShortcutsQuery();

internal sealed class ListKnownShortcutsQueryHandler
    : IUseCaseHandler<ListKnownShortcutsQuery, Result<KnownShortcutCatalogDto>>
{
    // Projected once: the manifest is immutable for the process lifetime.
    private static readonly KnownShortcutCatalogDto s_catalog = Project();

    public Task<Result<KnownShortcutCatalogDto>> ExecuteAsync(
        ListKnownShortcutsQuery request, CancellationToken ct) =>
        Task.FromResult(Result<KnownShortcutCatalogDto>.Success(s_catalog));

    private static KnownShortcutCatalogDto Project() => new(
    [
        .. KnownShortcutCatalog.All.Select(s => new KnownShortcutDto(
            s.Id, s.Key, s.Ctrl, s.Alt, s.Shift, s.Win,
            [.. s.Uses.Select(u => new ShortcutUseDto(u.UsedBy, u.Protection, u.Scope, u.Does))],
            s.WarningText))
    ]);
}
