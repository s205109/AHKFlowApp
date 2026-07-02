using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>One saved version of a tracked item.</summary>
/// <param name="Version">Monotonic 1-based version number.</param>
/// <param name="ChangeType">Whether this before-image was captured by an edit or a delete.</param>
/// <param name="CapturedAt">UTC timestamp of the change that produced this version.</param>
public sealed record HistoryEntryDto(int Version, HistoryChangeType ChangeType, DateTimeOffset CapturedAt);

/// <summary>Full saved version of a hotstring, including its snapshot for preview.</summary>
/// <param name="Version">Monotonic 1-based version number.</param>
/// <param name="ChangeType">Whether this before-image was captured by an edit or a delete.</param>
/// <param name="CapturedAt">UTC timestamp of the change that produced this version.</param>
/// <param name="Snapshot">The hotstring state at capture time.</param>
public sealed record HotstringHistoryVersionDto(
    int Version,
    HistoryChangeType ChangeType,
    DateTimeOffset CapturedAt,
    HotstringSnapshot Snapshot);

/// <summary>Full saved version of a hotkey, including its snapshot for preview.</summary>
/// <param name="Version">Monotonic 1-based version number.</param>
/// <param name="ChangeType">Whether this before-image was captured by an edit or a delete.</param>
/// <param name="CapturedAt">UTC timestamp of the change that produced this version.</param>
/// <param name="Snapshot">The hotkey state at capture time.</param>
public sealed record HotkeyHistoryVersionDto(
    int Version,
    HistoryChangeType ChangeType,
    DateTimeOffset CapturedAt,
    HotkeySnapshot Snapshot);

/// <summary>A deleted hotstring shown in the Recycle Bin.</summary>
/// <param name="Id">The original hotstring id; restore keeps it.</param>
/// <param name="Trigger">Trigger at deletion time.</param>
/// <param name="Replacement">Replacement at deletion time.</param>
/// <param name="Description">Description at deletion time.</param>
/// <param name="DeletedAt">UTC timestamp of the deletion.</param>
public sealed record DeletedHotstringDto(
    Guid Id,
    string Trigger,
    string Replacement,
    string? Description,
    DateTimeOffset DeletedAt);

/// <summary>A deleted hotkey shown in the Recycle Bin.</summary>
/// <param name="Id">The original hotkey id; restore keeps it.</param>
/// <param name="Description">Description at deletion time.</param>
/// <param name="Key">Main key at deletion time.</param>
/// <param name="Ctrl">Ctrl modifier.</param>
/// <param name="Alt">Alt modifier.</param>
/// <param name="Shift">Shift modifier.</param>
/// <param name="Win">Windows modifier.</param>
/// <param name="DeletedAt">UTC timestamp of the deletion.</param>
public sealed record DeletedHotkeyDto(
    Guid Id,
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    DateTimeOffset DeletedAt);
