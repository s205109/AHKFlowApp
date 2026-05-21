namespace AHKFlowApp.Application.DTOs;

public sealed record BulkDeleteResultDto(
    int DeletedCount,
    IReadOnlyList<Guid> MissingIds);
