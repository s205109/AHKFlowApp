using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>Draft hotkey fields to preview, without saving. Mirrors the create/update editable set.</summary>
/// <param name="Description">Human-readable label.</param>
/// <param name="Key">The main key, such as <c>F1</c> or <c>a</c>.</param>
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
public sealed record HotkeyPreviewRequestDto(
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
    string? Body = null) : IHotkeyDraft;

/// <summary>The AutoHotkey snippet a hotkey draft would generate.</summary>
/// <param name="Snippet">The exact <c>.ahk</c> line a save would produce for the given draft, including any <c>; </c> Description comment lines.</param>
public sealed record HotkeyPreviewDto(string Snippet);
