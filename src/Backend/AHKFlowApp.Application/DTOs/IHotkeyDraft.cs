using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>
/// The editable hotkey shape shared by create, update and preview: the activating combination plus
/// the typed action payload. <see cref="CreateHotkeyDto"/>, <see cref="UpdateHotkeyDto"/> and
/// <see cref="HotkeyPreviewRequestDto"/> satisfy it through their own positional properties, so it
/// costs no mapping code.
/// </summary>
/// <remarks>
/// It exists so the three things every one of those DTOs needs — the kind-conditional rules, the
/// §8 canonicalization, and the <see cref="Domain.Entities.HotkeyDefinition"/> build — are written
/// once. Passing the payload as one value also removes the eight same-typed positional arguments
/// the rules used to take, where transposing two <c>string?</c> selectors still compiled.
/// </remarks>
internal interface IHotkeyDraft
{
    string Description { get; }
    string Key { get; }
    bool Ctrl { get; }
    bool Alt { get; }
    bool Shift { get; }
    bool Win { get; }
    HotkeyActionKind ActionKind { get; }
    string? Text { get; }
    string? SendKeysContent { get; }
    string? RunTarget { get; }
    RunTargetKind? RunTargetKind { get; }
    WindowOp? WindowOp { get; }
    string? RemapDest { get; }
    string? Body { get; }
}
