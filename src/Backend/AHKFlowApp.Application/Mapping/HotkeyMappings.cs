using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotkeyMappings
{
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
