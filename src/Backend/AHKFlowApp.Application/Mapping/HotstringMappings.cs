using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Application.Services;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class HotstringMappings
{
    /// <summary>
    /// Copies back every field that <c>Hotstring.Apply</c> writes, so the rule check runs over the
    /// stored row (backlog 175).
    /// </summary>
    public static HotstringDefinition ToDefinition(this Hotstring h) => new(
        Trigger: h.Trigger,
        Replacement: h.Replacement,
        Description: h.Description,
        AppliesToAllProfiles: h.AppliesToAllProfiles,
        IsEndingCharacterRequired: h.IsEndingCharacterRequired,
        IsTriggerInsideWord: h.IsTriggerInsideWord,
        Kind: h.Kind,
        IsCaseSensitive: h.IsCaseSensitive,
        OmitEndingCharacter: h.OmitEndingCharacter,
        DateTimeFormat: h.DateTimeFormat,
        DateOffsetAmount: h.DateOffsetAmount,
        DateOffsetUnit: h.DateOffsetUnit,
        ContextMatchType: h.ContextMatchType,
        ContextValue: h.ContextValue,
        Delivery: h.Delivery);

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
