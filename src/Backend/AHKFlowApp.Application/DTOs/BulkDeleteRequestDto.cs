namespace AHKFlowApp.Application.DTOs;

/// <summary>Payload for deleting multiple entities by id.</summary>
/// <param name="Ids">Entity ids requested for deletion.</param>
public sealed record BulkDeleteRequestDto(Guid[] Ids);
