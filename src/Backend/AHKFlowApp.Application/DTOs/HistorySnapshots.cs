using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>Point-in-time snapshot of a hotstring aggregate, stored as history JSON.</summary>
/// <param name="Trigger">Abbreviation that activated the replacement.</param>
/// <param name="Replacement">Text that replaced the trigger.</param>
/// <param name="Description">Optional human-readable note.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applied to every profile.</param>
/// <param name="IsEndingCharacterRequired">AutoHotkey ending-character option at capture time.</param>
/// <param name="IsTriggerInsideWord">AutoHotkey inside-word option at capture time.</param>
/// <param name="ProfileIds">Profile links at capture time.</param>
/// <param name="CategoryIds">Category links at capture time.</param>
/// <param name="CreatedAt">Original creation timestamp.</param>
/// <param name="UpdatedAt">Last-update timestamp at capture time.</param>
/// <param name="Kind">Hotstring kind at capture time. Defaults to <see cref="HotstringKind.Text"/> for pre-Phase-1 snapshots.</param>
/// <param name="IsCaseSensitive">AutoHotkey's <c>C</c> option at capture time. Defaults to false for pre-Phase-1 snapshots.</param>
/// <param name="OmitEndingCharacter">AutoHotkey's <c>O</c> option at capture time. Defaults to false for pre-Phase-1 snapshots.</param>
/// <param name="DateTimeFormat">Date/time format token pattern at capture time. Defaults to null for pre-Phase-2 snapshots.</param>
/// <param name="DateOffsetAmount">Signed offset applied to the current date/time at capture time. Defaults to null for pre-Phase-2 snapshots.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/> at capture time. Defaults to null for pre-Phase-2 snapshots.</param>
/// <param name="ContextMatchType">Window-context match type at capture time. Defaults to null (global) for pre-Phase-4 snapshots.</param>
/// <param name="ContextValue">Window-context match value at capture time. Defaults to null (global) for pre-Phase-4 snapshots.</param>
/// <param name="Delivery">Requested delivery mode at capture time. Defaults to <see cref="HotstringDelivery.Auto"/> for legacy snapshots.</param>
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
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null,
    HotstringDelivery Delivery = HotstringDelivery.Auto);

/// <summary>
/// Point-in-time snapshot of a hotkey aggregate, stored as history JSON.
/// </summary>
/// <remarks>
/// Three shapes exist in the history table and all three must keep restoring:
/// <list type="bullet">
/// <item><description><b>Legacy</b> — written before W1: only <paramref name="Action"/> and
/// <paramref name="Parameters"/>. The typed members deserialize to their defaults.</description></item>
/// <item><description><b>Typed</b> — written from W1 on: the typed members carry the payload and the
/// legacy pair is null.</description></item>
/// <item><description><b>Mixed</b> — both present, e.g. a snapshot taken during the expand phase while
/// the entity still carried both. The legacy pair wins so the row restores as it always did.</description></item>
/// </list>
/// <see cref="AHKFlowApp.Application.Services.LegacyHotkeySnapshotConverter"/> resolves the shape.
/// The legacy members are permanent: rows already in the database still hold them.
/// </remarks>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applied to every profile.</param>
/// <param name="ProfileIds">Profile links at capture time.</param>
/// <param name="CategoryIds">Category links at capture time.</param>
/// <param name="CreatedAt">Original creation timestamp.</param>
/// <param name="UpdatedAt">Last-update timestamp at capture time.</param>
/// <param name="ActionKind">Typed action kind at capture time. Meaningless on a legacy snapshot.</param>
/// <param name="Text">Literal text for <see cref="HotkeyActionKind.SendText"/>.</param>
/// <param name="SendKeysContent">Key sequence for <see cref="HotkeyActionKind.SendKeys"/>.</param>
/// <param name="RunTarget">Application path or URL for <see cref="HotkeyActionKind.Run"/>.</param>
/// <param name="RunTargetKind">Whether <paramref name="RunTarget"/> is an application or a URL.</param>
/// <param name="WindowOp">Window operation for <see cref="HotkeyActionKind.Window"/>.</param>
/// <param name="RemapDest">Destination key for <see cref="HotkeyActionKind.Remap"/>.</param>
/// <param name="Body">Verbatim AutoHotkey body for <see cref="HotkeyActionKind.Raw"/>.</param>
/// <param name="Action">Legacy action kind. Present only in pre-W1 snapshots; the converter keys off it.</param>
/// <param name="Parameters">Legacy action-specific parameter payload. Present only in pre-W1 snapshots.</param>
public sealed record HotkeySnapshot(
    string Description,
    string Key,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    bool AppliesToAllProfiles,
    Guid[] ProfileIds,
    Guid[] CategoryIds,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    HotkeyActionKind ActionKind = HotkeyActionKind.Raw,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null,
    HotkeyAction? Action = null,
    string? Parameters = null);
