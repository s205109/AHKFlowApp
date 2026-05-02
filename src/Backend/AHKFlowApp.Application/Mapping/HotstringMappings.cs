using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotstringMappings
{
    public static HotstringDto ToDto(this Hotstring h) => new(
        h.Id,
        h.Profiles.Select(p => p.ProfileId).ToArray(),
        h.AppliesToAllProfiles,
        h.Trigger,
        h.Replacement,
        h.IsEndingCharacterRequired,
        h.IsTriggerInsideWord,
        h.CreatedAt,
        h.UpdatedAt);
}
