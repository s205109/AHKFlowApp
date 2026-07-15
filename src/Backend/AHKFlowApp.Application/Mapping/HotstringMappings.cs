using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
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
        h.Description,
        h.IsEndingCharacterRequired,
        h.IsTriggerInsideWord,
        h.CreatedAt,
        h.UpdatedAt,
        h.Categories.Select(hc => hc.CategoryId).ToArray(),
        h.Kind,
        h.IsCaseSensitive,
        h.OmitEndingCharacter,
        h.DateTimeFormat,
        h.DateOffsetAmount,
        h.DateOffsetUnit,
        h.ContextMatchType,
        h.ContextValue,
        h.Delivery,
        EffectiveDelivery: HotstringEmitter.ResolveEffectiveDelivery(h));
}
