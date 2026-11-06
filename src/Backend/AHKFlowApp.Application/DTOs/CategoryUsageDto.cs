namespace AHKFlowApp.Application.DTOs;

/// <summary>How many of the owner's items use one category.</summary>
/// <param name="HotstringCount">Number of hotstrings linked to the category.</param>
/// <param name="HotkeyCount">Number of hotkeys linked to the category.</param>
public sealed record CategoryUsageDto(
    int HotstringCount,
    int HotkeyCount);
