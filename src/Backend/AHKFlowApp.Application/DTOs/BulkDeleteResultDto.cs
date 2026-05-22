namespace AHKFlowApp.Application.DTOs;

/// <summary>Result summary for a bulk-delete request.</summary>
/// <param name="DeletedCount">Number of entities deleted.</param>
/// <param name="MissingIds">Requested ids that were not found.</param>
public sealed record BulkDeleteResultDto(
    int DeletedCount,
    IReadOnlyList<Guid> MissingIds);
