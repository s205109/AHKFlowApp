namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>One ready-made block an owner can append to a Profile header.</summary>
public sealed record HeaderPresetDto(
    string Id,
    string Name,
    string Description,
    string Tag,
    string Body);

/// <summary>The shipped preset list, in catalog order. Bodies always come from the API.</summary>
public sealed record HeaderPresetCatalogDto(IReadOnlyList<HeaderPresetDto> Presets);
