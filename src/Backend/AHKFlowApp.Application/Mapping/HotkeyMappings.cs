using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotkeyMappings
{
    public static HotkeyDto ToDto(this Hotkey h) => new(
        h.Id,
        h.ProfileId,
        h.Trigger,
        h.Action,
        h.Description,
        h.CreatedAt,
        h.UpdatedAt);
}
