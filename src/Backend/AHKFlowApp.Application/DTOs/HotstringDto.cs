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
/// <param name="Kind">Hotstring kind. <see cref="HotstringKind.Text"/>, <see cref="HotstringKind.DateTime"/>, <see cref="HotstringKind.Macro"/>, and <see cref="HotstringKind.Raw"/> are all supported via the API.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
/// <param name="DateTimeFormat">Set when <paramref name="Kind"/> is <see cref="HotstringKind.DateTime"/>; a whitelisted AHK/.NET date/time token pattern.</param>
/// <param name="DateOffsetAmount">Optional signed offset applied to the current date/time; requires <paramref name="DateOffsetUnit"/>.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/>; requires <paramref name="DateOffsetAmount"/>.</param>
/// <param name="ContextMatchType">How <paramref name="ContextValue"/> is matched against the active window; requires <paramref name="ContextValue"/>. Kind-agnostic.</param>
/// <param name="ContextValue">Value matched against the active window (executable name, window class, or title substring, per <paramref name="ContextMatchType"/>); requires <paramref name="ContextMatchType"/>.</param>
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
    bool OmitEndingCharacter = false,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null);

/// <summary>Payload to create a new hotstring.</summary>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="ProfileIds">Profiles to attach the new hotstring to. Ignored when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applies to every profile and <paramref name="ProfileIds"/> is ignored.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
/// <param name="Description">Optional human-readable note for the hotstring.</param>
/// <param name="CategoryIds">Categories to assign to the new hotstring.</param>
/// <param name="Kind">Hotstring kind. <see cref="HotstringKind.Text"/>, <see cref="HotstringKind.DateTime"/>, <see cref="HotstringKind.Macro"/>, and <see cref="HotstringKind.Raw"/> are all supported via the API.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
/// <param name="DateTimeFormat">Required when <paramref name="Kind"/> is <see cref="HotstringKind.DateTime"/>; a whitelisted AHK/.NET date/time token pattern.</param>
/// <param name="DateOffsetAmount">Optional signed offset applied to the current date/time; requires <paramref name="DateOffsetUnit"/>.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/>; requires <paramref name="DateOffsetAmount"/>.</param>
/// <param name="ContextMatchType">How <paramref name="ContextValue"/> is matched against the active window; requires <paramref name="ContextValue"/>. Kind-agnostic.</param>
/// <param name="ContextValue">Value matched against the active window (executable name, window class, or title substring, per <paramref name="ContextMatchType"/>); requires <paramref name="ContextMatchType"/>.</param>
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
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null);

/// <summary>Payload to replace the editable fields of an existing hotstring.</summary>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="ProfileIds">Replacement profile-attachment set. Ignored when <paramref name="AppliesToAllProfiles"/> is true.</param>
/// <param name="AppliesToAllProfiles">When true, the hotstring applies to every profile.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
/// <param name="Description">Optional human-readable note for the hotstring.</param>
/// <param name="CategoryIds">Replacement category assignment set.</param>
/// <param name="Kind">Hotstring kind. <see cref="HotstringKind.Text"/>, <see cref="HotstringKind.DateTime"/>, <see cref="HotstringKind.Macro"/>, and <see cref="HotstringKind.Raw"/> are all supported via the API.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
/// <param name="DateTimeFormat">Required when <paramref name="Kind"/> is <see cref="HotstringKind.DateTime"/>; a whitelisted AHK/.NET date/time token pattern.</param>
/// <param name="DateOffsetAmount">Optional signed offset applied to the current date/time; requires <paramref name="DateOffsetUnit"/>.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/>; requires <paramref name="DateOffsetAmount"/>.</param>
/// <param name="ContextMatchType">How <paramref name="ContextValue"/> is matched against the active window; requires <paramref name="ContextValue"/>. Kind-agnostic.</param>
/// <param name="ContextValue">Value matched against the active window (executable name, window class, or title substring, per <paramref name="ContextMatchType"/>); requires <paramref name="ContextMatchType"/>.</param>
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
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null);

/// <summary>Emission-relevant fields for previewing the AutoHotkey snippet a hotstring definition would generate, without saving it.</summary>
/// <param name="Kind">Hotstring kind. <see cref="HotstringKind.Text"/>, <see cref="HotstringKind.DateTime"/>, <see cref="HotstringKind.Macro"/>, and <see cref="HotstringKind.Raw"/> are all supported.</param>
/// <param name="Trigger">Abbreviation that activates the replacement.</param>
/// <param name="Replacement">Text inserted in place of the trigger.</param>
/// <param name="IsCaseSensitive">Controls AutoHotkey's <c>C</c> option.</param>
/// <param name="OmitEndingCharacter">Controls AutoHotkey's <c>O</c> option.</param>
/// <param name="IsEndingCharacterRequired">Controls AutoHotkey's <c>*</c> option.</param>
/// <param name="IsTriggerInsideWord">Controls AutoHotkey's <c>?</c> option.</param>
/// <param name="DateTimeFormat">Required when <paramref name="Kind"/> is <see cref="HotstringKind.DateTime"/>; a whitelisted AHK/.NET date/time token pattern.</param>
/// <param name="DateOffsetAmount">Optional signed offset applied to the current date/time; requires <paramref name="DateOffsetUnit"/>.</param>
/// <param name="DateOffsetUnit">Unit for <paramref name="DateOffsetAmount"/>; requires <paramref name="DateOffsetAmount"/>.</param>
/// <param name="ContextMatchType">How <paramref name="ContextValue"/> is matched against the active window; requires <paramref name="ContextValue"/>. Kind-agnostic.</param>
/// <param name="ContextValue">Value matched against the active window (executable name, window class, or title substring, per <paramref name="ContextMatchType"/>); requires <paramref name="ContextMatchType"/>.</param>
/// <param name="Description">Optional note previewed as <c>; </c> comment lines above the definition; for Raw, merged with any lifted comment.</param>
public sealed record HotstringPreviewRequestDto(
    HotstringKind Kind,
    string Trigger,
    string Replacement,
    bool IsCaseSensitive,
    bool OmitEndingCharacter,
    bool IsEndingCharacterRequired,
    bool IsTriggerInsideWord,
    string? DateTimeFormat = null,
    int? DateOffsetAmount = null,
    DateOffsetUnit? DateOffsetUnit = null,
    WindowMatchType? ContextMatchType = null,
    string? ContextValue = null,
    string? Description = null);

/// <summary>The AutoHotkey snippet a hotstring definition would generate.</summary>
/// <param name="Snippet">The exact <c>.ahk</c> line(s) a save would produce for the given definition, including any <c>; </c> Description comment lines.</param>
/// <param name="RawSummary">Server-derived summary for a Raw definition; null for other kinds.</param>
public sealed record HotstringPreviewDto(string Snippet, RawSummaryDto? RawSummary = null);

/// <summary>Body shape of a Raw hotstring definition, surfaced in the preview summary.</summary>
public enum RawBodyKind
{
    /// <summary>No recognizable body (structurally invalid).</summary>
    None,

    /// <summary>Inline replacement on the definition line.</summary>
    Inline,

    /// <summary>AutoHotkey code block <c>{ … }</c>.</summary>
    Braces,

    /// <summary>Literal multi-line text continuation section <c>( … )</c>.</summary>
    Continuation,
}

/// <summary>Parsed summary of a Raw hotstring definition, shown below the editor's raw textarea.</summary>
/// <param name="Trigger">Trigger derived from the definition's first line.</param>
/// <param name="OptionTokens">Option flags parsed from the definition, in first-line order.</param>
/// <param name="BodyKind">Classified body shape (code block vs multi-line text vs inline).</param>
/// <param name="BodyLineCount">Literal line count for a continuation body; 0 for other shapes.</param>
/// <param name="LiftedComment">Leading comment text a save would move into Description; null when none.</param>
public sealed record RawSummaryDto(
    string Trigger,
    string[] OptionTokens,
    RawBodyKind BodyKind,
    int BodyLineCount,
    string? LiftedComment);
