namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record BulkDeleteResultDto(
    int DeletedCount,
    IReadOnlyList<Guid> MissingIds);
