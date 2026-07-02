namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record ChangelogDocumentDto(
    int SchemaVersion,
    IReadOnlyList<ChangelogEntryDto> Entries);

public sealed record ChangelogEntryDto(
    string Version,
    string? Date,
    bool IsUnreleased,
    IReadOnlyList<ChangelogSectionDto> Sections);

public sealed record ChangelogSectionDto(
    string Name,
    IReadOnlyList<string> Items);
