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
        if (s.Action is HotkeyAction legacyAction)
        {
            LegacyHotkeyDefinitionConverter.TypedAction t =
                LegacyHotkeyDefinitionConverter.ToTyped(legacyAction, s.Parameters ?? "");

            return Definition(s, legacyAction, s.Parameters ?? "") with
            {
                ActionKind = t.ActionKind,
                Text = t.Text,
                SendKeysContent = t.SendKeysContent,
                RunTarget = t.RunTarget,
                RunTargetKind = t.RunTargetKind,
                WindowOp = t.WindowOp,
                RemapDest = t.RemapDest,
                Body = t.Body,
            };
        }

        // A W1 snapshot: pass the typed fields through (legacy pair vestigial until Migration B).
        return Definition(s, HotkeyAction.Send, "") with
        {
            ActionKind = s.ActionKind,
            Text = s.Text,
            SendKeysContent = s.SendKeysContent,
            RunTarget = s.RunTarget,
            RunTargetKind = s.RunTargetKind,
            WindowOp = s.WindowOp,
            RemapDest = s.RemapDest,
            Body = s.Body,
        };
    }

    private static HotkeyDefinition Definition(HotkeySnapshot s, HotkeyAction action, string parameters) =>
        new(
            Description: s.Description,
            Key: s.Key,
            Ctrl: s.Ctrl,
            Alt: s.Alt,
            Shift: s.Shift,
            Win: s.Win,
            Action: action,
            Parameters: parameters,
            AppliesToAllProfiles: s.AppliesToAllProfiles);
}
