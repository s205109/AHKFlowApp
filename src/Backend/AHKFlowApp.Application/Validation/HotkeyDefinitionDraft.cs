using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Validation;

/// <summary>
/// Reads a <see cref="HotkeyDefinition"/> as an <see cref="IHotkeyDraft"/>, so the hotkey action
/// rules apply to it with no change. The adapter lives in Application because Domain references
/// nothing and so cannot implement an Application interface.
/// <para>
/// <c>AppliesToAllProfiles</c> is absent from <see cref="IHotkeyDraft"/> and stays absent here:
/// profile scope is not a rule this check covers.
/// </para>
/// </summary>
internal sealed record HotkeyDefinitionDraft(HotkeyDefinition Definition) : IHotkeyDraft
{
    public string Description => Definition.Description;
    public string Key => Definition.Key;
    public bool Ctrl => Definition.Ctrl;
    public bool Alt => Definition.Alt;
    public bool Shift => Definition.Shift;
    public bool Win => Definition.Win;
    public HotkeyActionKind ActionKind => Definition.ActionKind;
    public string? Text => Definition.Text;
    public string? SendKeysContent => Definition.SendKeysContent;
    public string? RunTarget => Definition.RunTarget;
    public RunTargetKind? RunTargetKind => Definition.RunTargetKind;
    public WindowOp? WindowOp => Definition.WindowOp;
    public string? RemapDest => Definition.RemapDest;
    public string? Body => Definition.Body;
    public WindowMatchType? ContextMatchType => Definition.ContextMatchType;
    public string? ContextValue => Definition.ContextValue;
}
