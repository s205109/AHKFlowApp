namespace AHKFlowApp.UI.Blazor.DTOs;

public enum HistoryChangeType
{
    Edit = 1,
    Delete = 2,
    Restore = 3,
}

public sealed record HistoryEntryDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt);

public sealed record HotstringSnapshot(
    string Trigger,
    string Replacement,
    string? Description,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyAction Action,
    string Parameters,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

public sealed record HotstringHistoryVersionDto(
    int Version,
    HistoryChangeType ChangeType,
    DateTimeOffset CapturedAt,
    HotstringSnapshot Snapshot);

public sealed record HotkeyHistoryVersionDto(
    int Version,
    HistoryChangeType ChangeType,
    DateTimeOffset CapturedAt,
    HotkeySnapshot Snapshot);

public sealed record DeletedHotstringDto(
    Guid Id,
    string Trigger,
    string Replacement,
    string? Description,
    DateTimeOffset DeletedAt);

public sealed record DeletedHotkeyDto(
    Guid Id,
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    DateTimeOffset DeletedAt);
