namespace AHKFlowApp.Application.DTOs;

/// <summary>Counts returned after seeding demo data for development.</summary>
/// <param name="CategoriesCount">Number of categories created or already present.</param>
/// <param name="HotstringsCount">Number of hotstrings created or already present.</param>
/// <param name="HotkeysCount">Number of hotkeys created or already present.</param>
public sealed record SeedAllResultDto(
    int CategoriesCount,
    int HotstringsCount,
    int HotkeysCount);
