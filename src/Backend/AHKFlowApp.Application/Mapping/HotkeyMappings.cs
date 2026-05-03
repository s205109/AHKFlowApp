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
        h.Action,
        h.Parameters,
        h.CreatedAt,
        h.UpdatedAt);
}
