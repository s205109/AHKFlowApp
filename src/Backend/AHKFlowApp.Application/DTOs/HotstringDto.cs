using AHKFlowApp.Domain.Enums;

namespace AHKFlowApp.Application.DTOs;

/// <summary>A hotstring (text trigger plus replacement) owned by the current user.</summary>
/// <param name="Id">Server-generated identifier.</param>
/// <param name="ProfileIds">Profiles the hotstring is attached to. Empty when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring is included in every profile the user owns.</param>
/// <param name="Trigger">Abbreviation that activates the replacement, such as <c>btw</c>.</param>
/// <param name="Replacement">Text that replaces the trigger, such as <c>by the way</c>.</param>
/// <param name="Description">Optional human-readable note for the hotstring.</param>
/// <param name="IsEndingCharacterRequired">When true, AutoHotkey requires a trailing whitespace or punctuation character to fire.</param>
/// <param name="IsTriggerInsideWord">When true, the trigger matches even inside a larger word.</param>
/// <param name="CreatedAt">UTC creation timestamp.</param>
/// <param name="UpdatedAt">UTC last-update timestamp.</param>
/// <param name="CategoryIds">Categories assigned to this hotstring.</param>
/// <param name="Kind">Hotstring kind. Phase 1 only supports <see cref="HotstringKind.Text"/>.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
public sealed record HotstringDto(
    Guid Id,
    Guid[] ProfileIds,
    bool AppliesToAllProfiles,
    string Trigger,
    string Replacement,
    string? Description,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    Guid[] CategoryIds,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false);

/// <summary>Payload to create a new hotstring.</summary>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="ProfileIds">Profiles to attach the new hotstring to. Ignored when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applies to every profile and <paramref name="ProfileIds"/> is ignored.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
/// <param name="Description">Optional human-readable note for the hotstring.</param>
/// <param name="CategoryIds">Categories to assign to the new hotstring.</param>
/// <param name="Kind">Hotstring kind. Phase 1 only supports <see cref="HotstringKind.Text"/>.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
/// <param name="DateTimeFormat">Required when <paramref name="Kind"/> is <see cref="HotstringKind.DateTime"/>; a whitelisted AHK/.NET date/time token pattern.</param>
/// <param name="DateOffsetAmount">Optional signed offset applied to the current date/time; requires <paramref name="DateOffsetUnit"/>.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/>; requires <paramref name="DateOffsetAmount"/>.</param>
public sealed record CreateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds = null,
    bool AppliesToAllProfiles = true,
    bool IsEndingCharacterRequired = true,
    bool IsTriggerInsideWord = true,
    string? Description = null,
    Guid[]? CategoryIds = null,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null);

/// <summary>Payload to replace the editable fields of an existing hotstring.</summary>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="ProfileIds">Replacement profile-attachment set. Ignored when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applies to every profile.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
/// <param name="Description">Optional human-readable note for the hotstring.</param>
/// <param name="CategoryIds">Replacement category assignment set.</param>
/// <param name="Kind">Hotstring kind. Phase 1 only supports <see cref="HotstringKind.Text"/>.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
/// <param name="DateTimeFormat">Required when <paramref name="Kind"/> is <see cref="HotstringKind.DateTime"/>; a whitelisted AHK/.NET date/time token pattern.</param>
/// <param name="DateOffsetAmount">Optional signed offset applied to the current date/time; requires <paramref name="DateOffsetUnit"/>.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/>; requires <paramref name="DateOffsetAmount"/>.</param>
public sealed record UpdateHotstringDto(
    string Trigger,
    string Replacement,
    Guid[]? ProfileIds,
    bool AppliesToAllProfiles,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string? Description,
    Guid[]? CategoryIds = null,
    HotstringKind Kind = HotstringKind.Text,
    bool IsCaseSensitive = false,
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null);
