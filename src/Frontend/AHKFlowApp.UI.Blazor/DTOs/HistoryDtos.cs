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
    DateTimeOffset UpdatedAt,
    HotstringKind Kind = HotstringKind.Text,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null,
    HotstringDelivery Delivery = HotstringDelivery.Auto);

public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    HotkeyActionKind ActionKind,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    // Optional legacy members, permanently. Old history JSON still carries them, and the
    // backend keeps them on its own HotkeySnapshot for exactly that reason (backend Task 8).
    // Unlike the DTO pair above, these do NOT retire in Task 10.
    HotkeyAction? Action = null,
    string? Parameters = null);

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
