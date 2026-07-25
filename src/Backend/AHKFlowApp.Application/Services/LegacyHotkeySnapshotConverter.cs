using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;
using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.Services;

/// <summary>
/// Builds the <see cref="HotkeyDefinition"/> to persist when restoring or reverting a
/// <see cref="HotkeySnapshot"/>. A pre-W1 snapshot (legacy <see cref="HotkeySnapshot.Action"/> present)
/// is converted through the same rules as the data migration via
/// <see cref="LegacyHotkeyDefinitionConverter"/>; a W1 snapshot is applied as-is. The
/// <c>ScriptToRawComposer.ToDefinition</c> analogue (spec §8).
/// </summary>
public static class LegacyHotkeySnapshotConverter
{
    /// <summary>Resolves <paramref name="s"/> — legacy-, typed-, or mixed-shaped — into typed columns.</summary>
    public static HotkeyDefinition ToDefinition(HotkeySnapshot s)
    {
        // A legacy snapshot: derive the typed columns from the legacy pair. Mixed snapshots take this
        // arm too, so a row keeps restoring to exactly what it restored to before the typed members
        // existed.
        if (s.Action is LegacyHotkeyDefinitionConverter.HotkeyAction legacyAction)
        {
            return LegacyHotkeyDefinitionConverter.FromLegacy(
                description: s.Description,
                key: s.Key,
                ctrl: s.Ctrl,
                alt: s.Alt,
                shift: s.Shift,
                win: s.Win,
                action: legacyAction,
                parameters: s.Parameters ?? "",
                appliesToAllProfiles: s.AppliesToAllProfiles);
        }

        // A W1 snapshot: pass the typed fields through.
        return new HotkeyDefinition(
            Description: s.Description,
            Key: s.Key,
            Ctrl: s.Ctrl,
            Alt: s.Alt,
            Shift: s.Shift,
            Win: s.Win,
            ActionKind: s.ActionKind,
            AppliesToAllProfiles: s.AppliesToAllProfiles,
            Text: s.Text,
            SendKeysContent: s.SendKeysContent,
            RunTarget: s.RunTarget,
            RunTargetKind: s.RunTargetKind,
            WindowOp: s.WindowOp,
            RemapDest: s.RemapDest,
            Body: s.Body);
    }
}
