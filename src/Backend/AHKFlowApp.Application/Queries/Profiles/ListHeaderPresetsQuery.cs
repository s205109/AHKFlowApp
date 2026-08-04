using AHKFlowApp.Application.Abstractions;
using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using Ardalis.Result;

namespace AHKFlowApp.Application.Queries.Profiles;

/// <summary>Returns the shipped header presets for the profile header picker. Static reference data.</summary>
public sealed record ListHeaderPresetsQuery();

internal sealed class ListHeaderPresetsQueryHandler
    : IUseCaseHandler<ListHeaderPresetsQuery, Result<HeaderPresetCatalogDto>>
{
    // Projected once: the catalog is immutable for the process lifetime.
    private static readonly HeaderPresetCatalogDto s_catalog = Project();

    public Task<Result<HeaderPresetCatalogDto>> ExecuteAsync(
        ListHeaderPresetsQuery request, CancellationToken ct) =>
        Task.FromResult(Result<HeaderPresetCatalogDto>.Success(s_catalog));

    private static HeaderPresetCatalogDto Project() => new(
        [.. HeaderPresetCatalog.All.Select(p =>
            new HeaderPresetDto(p.Id, p.Name, p.Description, p.Tag, p.Body))]);
}
