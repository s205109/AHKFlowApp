namespace AHKFlowApp.Application.DTOs;

/// <summary>Payload to create a new category.</summary>
/// <param name="Name">Category name. Must be unique per user.</param>
public sealed record CreateCategoryDto(string Name);
