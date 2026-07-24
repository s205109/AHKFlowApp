using AHKFlowApp.Application.Constants;
using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Validation;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotkeyMappings
{
    /// <summary>
    /// Builds the persisted/emitted definition from a validated draft, canonicalizing the key and
    /// the two token fields on the way (spec §8 storage invariant). Create, update and preview all
    /// come through here, so a draft previews exactly as it would save.
    /// </summary>
    /// <remarks>
    /// The <see cref="HotkeyKeys.TryCanonicalize"/> return value is ignored: the validator rejects
    /// unknown keys before any handler runs, so it always succeeds here. Normalization of the token
    /// fields is likewise safe on values the validator has already accepted — and a no-op on the
    /// nulls every other kind carries.
    /// </remarks>
    public static HotkeyDefinition ToDefinition(this IHotkeyDraft d, bool appliesToAllProfiles)
    {
        HotkeyKeys.TryCanonicalize(d.Key, out string canonicalKey);

        return new HotkeyDefinition(
            Description: d.Description,
            Key: canonicalKey,
            Ctrl: d.Ctrl,
            Alt: d.Alt,
            Shift: d.Shift,
            Win: d.Win,
            ActionKind: d.ActionKind,
            AppliesToAllProfiles: appliesToAllProfiles,
            Text: d.Text,
            SendKeysContent: HotkeyRules.Tokens.NormalizeSendKeysContent(d.SendKeysContent),
            RunTarget: d.RunTarget,
            RunTargetKind: d.RunTargetKind,
            WindowOp: d.WindowOp,
            RemapDest: HotkeyRules.Tokens.NormalizeRemapDest(d.RemapDest),
            Body: d.Body);
    }

    public static HotkeyDto ToDto(this Hotkey h) => new(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Description,
        h.Key,
        h.Ctrl,
        h.Alt,
        h.Shift,
        h.Win,
        h.ActionKind,
        h.Text,
        h.SendKeysContent,
        h.RunTarget,
        h.RunTargetKind,
        h.WindowOp,
        h.RemapDest,
        h.Body,
        h.CreatedAt,
        h.UpdatedAt,
        h.Categories.Select(c => c.CategoryId).ToArray());
}
