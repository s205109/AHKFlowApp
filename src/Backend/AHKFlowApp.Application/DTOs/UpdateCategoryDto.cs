namespace AHKFlowApp.Application.DTOs;

/// <summary>Payload to rename an existing category.</summary>
/// <param name="Name">Replacement category name. Must be unique per user.</param>
public sealed record UpdateCategoryDto(string Name);
