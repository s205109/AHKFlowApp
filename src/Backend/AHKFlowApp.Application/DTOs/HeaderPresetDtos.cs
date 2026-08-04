namespace AHKFlowApp.Application.DTOs;

/// <summary>One ready-made block an owner can append to a Profile header.</summary>
/// <param name="Id">Stable kebab-case id. It appears in the marker comments the picker writes.</param>
/// <param name="Name">Picker heading.</param>
/// <param name="Description">One line saying what the preset does.</param>
/// <param name="Tag">Picker grouping label.</param>
/// <param name="Body">The AutoHotkey text, without markers.</param>
public sealed record HeaderPresetDto(
    string Id,
    string Name,
    string Description,
    string Tag,
    string Body);

/// <summary>The whole shipped preset list, in catalog order.</summary>
public sealed record HeaderPresetCatalogDto(IReadOnlyList<HeaderPresetDto> Presets);
