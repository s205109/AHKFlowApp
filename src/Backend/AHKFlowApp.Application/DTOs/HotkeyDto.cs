using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>A keyboard hotkey binding owned by the current user.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="ProfileIds">Profiles the hotkey is attached to.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey is included in every profile the user owns.</param>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">The main key, such as <c>F1</c> or <c>a</c>.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="ActionKind">Which typed action the hotkey performs.</param>
/// <param name="Text">Literal text sent by a <see cref="HotkeyActionKind.SendText"/> hotkey.</param>
/// <param name="SendKeysContent">Key token sent by a <see cref="HotkeyActionKind.SendKeys"/> hotkey.</param>
/// <param name="RunTarget">Application, document or URL launched by a <see cref="HotkeyActionKind.Run"/> hotkey.</param>
/// <param name="RunTargetKind">How <paramref name="RunTarget"/> is interpreted.</param>
/// <param name="WindowOp">Window operation performed by a <see cref="HotkeyActionKind.Window"/> hotkey.</param>
/// <param name="RemapDest">Destination key of a <see cref="HotkeyActionKind.Remap"/> hotkey.</param>
/// <param name="Body">Verbatim AHK body emitted by a <see cref="HotkeyActionKind.Raw"/> hotkey.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
/// <param name="CategoryIds">Categories assigned to this hotkey.</param>
public sealed record HotkeyDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
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
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[] CategoryIds);

/// <summary>Payload to create a new hotkey.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="ActionKind">Which typed action the hotkey performs.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Text">Literal text sent by a <see cref="HotkeyActionKind.SendText"/> hotkey.</param>
/// <param name="SendKeysContent">Key token sent by a <see cref="HotkeyActionKind.SendKeys"/> hotkey.</param>
/// <param name="RunTarget">Application, document or URL launched by a <see cref="HotkeyActionKind.Run"/> hotkey.</param>
/// <param name="RunTargetKind">How <paramref name="RunTarget"/> is interpreted.</param>
/// <param name="WindowOp">Window operation performed by a <see cref="HotkeyActionKind.Window"/> hotkey.</param>
/// <param name="RemapDest">Destination key of a <see cref="HotkeyActionKind.Remap"/> hotkey.</param>
/// <param name="Body">Verbatim AHK body emitted by a <see cref="HotkeyActionKind.Raw"/> hotkey.</param>
/// <param name="ProfileIds">Profiles to attach the new hotkey to.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applies to every profile.</param>
/// <param name="CategoryIds">Categories to assign to the new hotkey.</param>
public sealed record CreateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl = false,
    bool Alt = false,
    bool Shift = false,
    bool Win = false,
    string? Text = null,
    string? SendKeysContent = null,
    string? RunTarget = null,
    RunTargetKind? RunTargetKind = null,
    WindowOp? WindowOp = null,
    string? RemapDest = null,
    string? Body = null,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = false,
    Guid[]? CategoryIds = null);

/// <summary>Payload to replace the editable fields of an existing hotkey.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">Main key.</param>
/// <param name="ActionKind">Which typed action the hotkey performs.</param>
/// <param name="Ctrl">Ctrl modifier required.</param>
/// <param name="Alt">Alt modifier required.</param>
/// <param name="Shift">Shift modifier required.</param>
/// <param name="Win">Windows modifier required.</param>
/// <param name="Text">Literal text sent by a <see cref="HotkeyActionKind.SendText"/> hotkey.</param>
/// <param name="SendKeysContent">Key token sent by a <see cref="HotkeyActionKind.SendKeys"/> hotkey.</param>
/// <param name="RunTarget">Application, document or URL launched by a <see cref="HotkeyActionKind.Run"/> hotkey.</param>
/// <param name="RunTargetKind">How <paramref name="RunTarget"/> is interpreted.</param>
/// <param name="WindowOp">Window operation performed by a <see cref="HotkeyActionKind.Window"/> hotkey.</param>
/// <param name="RemapDest">Destination key of a <see cref="HotkeyActionKind.Remap"/> hotkey.</param>
/// <param name="Body">Verbatim AHK body emitted by a <see cref="HotkeyActionKind.Raw"/> hotkey.</param>
/// <param name="ProfileIds">Replacement profile-attachment set.</param>
/// <param name="AppliesToAllProfiles">When true, the hotkey applies to every profile.</param>
/// <param name="CategoryIds">Replacement category assignment set.</param>
public sealed record UpdateHotkeyDto(
    string Description,
    string Key,
    HotkeyActionKind ActionKind,
    bool Ctrl,
    bool Alt,
    bool Shift,
    bool Win,
    string? Text,
    string? SendKeysContent,
    string? RunTarget,
    RunTargetKind? RunTargetKind,
    WindowOp? WindowOp,
    string? RemapDest,
    string? Body,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    Guid[]? CategoryIds = null);
