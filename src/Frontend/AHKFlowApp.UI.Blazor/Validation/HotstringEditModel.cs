using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotstringEditModel
{
    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Trigger is required.")]
    [MaxLength(50, ErrorMessage = "Trigger must be 50 characters or fewer.")]
    public string Trigger { get; set; } = "";

    // Requiredness is conditional on Kind (not required for DateTime) — enforced by the
    // dialog's field-level Required param (Task 10) and by server-side validation.
    [MaxLength(4000, ErrorMessage = "Replacement must be 4000 characters or fewer.")]
    public string Replacement { get; set; } = "";

    [MaxLength(200, ErrorMessage = "Description must be 200 characters or fewer.")]
    public string? Description { get; set; }

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];
    public bool IsEndingCharacterRequired { get; set; } = true;
    public bool IsTriggerInsideWord { get; set; } = true;
    public List<Guid> CategoryIds { get; set; } = [];
    public HotstringKind Kind { get; set; } = HotstringKind.Text;
    public bool IsCaseSensitive { get; set; }
    public bool OmitEndingCharacter { get; set; }
    public string? DateTimeFormat { get; set; }
    public int? DateOffsetAmount { get; set; }
    public DateOffsetUnit? DateOffsetUnit { get; set; }

    /// <summary>UI-facing inverse of <see cref="IsEndingCharacterRequired"/> (spec label "Expand immediately").</summary>
    public bool ExpandImmediately
    {
        get => !IsEndingCharacterRequired;
        set => IsEndingCharacterRequired = !value;
    }

    /// <summary>Grid rows can only offer inline edit for Text-kind hotstrings (Task 11).</summary>
    public bool IsInlineEditable => Kind == HotstringKind.Text;

    /// <summary>
    /// Humanized date/time summary for grid/mobile display. Null unless <see cref="Kind"/> is
    /// <see cref="HotstringKind.DateTime"/> — callers fall back to plain Replacement text otherwise.
    /// Mirrors AHKFlowApp.CLI.Output.HotstringTableFormatter's FormatReplacementColumn logic.
    /// </summary>
    public string? DateTimeSummary
    {
        get
        {
            if (Kind != HotstringKind.DateTime) return null;
            if (DateTimeFormat is null) return "—";
            if (DateOffsetAmount is null || DateOffsetUnit is null) return DateTimeFormat;

            int amount = DateOffsetAmount.Value;
            string sign = amount < 0 ? "-" : "+";
            string unitName = FormatUnitName(DateOffsetUnit.Value, amount);
            return $"{DateTimeFormat} ({sign}{Math.Abs(amount)} {unitName})";
        }
    }

    public static HotstringEditModel FromDto(HotstringDto dto) => new()
    {
        Id = dto.Id,
        Trigger = dto.Trigger,
        Replacement = dto.Replacement,
        Description = dto.Description,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
        IsEndingCharacterRequired = dto.IsEndingCharacterRequired,
        IsTriggerInsideWord = dto.IsTriggerInsideWord,
        CategoryIds = [.. dto.CategoryIds ?? []],
        Kind = dto.Kind,
        IsCaseSensitive = dto.IsCaseSensitive,
        OmitEndingCharacter = dto.OmitEndingCharacter,
        DateTimeFormat = dto.DateTimeFormat,
        DateOffsetAmount = dto.DateOffsetAmount,
        DateOffsetUnit = dto.DateOffsetUnit,
    };

    public HotstringEditModel Clone() => new()
    {
        Id = Id,
        Trigger = Trigger,
        Replacement = Replacement,
        Description = Description,
        AppliesToAllProfiles = AppliesToAllProfiles,
        ProfileIds = [.. ProfileIds],
        IsEndingCharacterRequired = IsEndingCharacterRequired,
        IsTriggerInsideWord = IsTriggerInsideWord,
        CategoryIds = [.. CategoryIds],
        Kind = Kind,
        IsCaseSensitive = IsCaseSensitive,
        OmitEndingCharacter = OmitEndingCharacter,
        DateTimeFormat = DateTimeFormat,
        DateOffsetAmount = DateOffsetAmount,
        DateOffsetUnit = DateOffsetUnit,
    };

    public CreateHotstringDto ToCreateDto()
    {
        string replacement = Kind == HotstringKind.DateTime ? "" : Replacement;
        return new(Trigger, replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles,
            IsEndingCharacterRequired, IsTriggerInsideWord, Description, [.. CategoryIds], Kind, IsCaseSensitive,
            OmitEndingCharacter, DateTimeFormat, DateOffsetAmount, DateOffsetUnit);
    }

    public UpdateHotstringDto ToUpdateDto()
    {
        string replacement = Kind == HotstringKind.DateTime ? "" : Replacement;
        return new(Trigger, replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles,
            IsEndingCharacterRequired, IsTriggerInsideWord, Description, [.. CategoryIds], Kind, IsCaseSensitive,
            OmitEndingCharacter, DateTimeFormat, DateOffsetAmount, DateOffsetUnit);
    }

    /// <summary>
    /// Previews what <paramref name="format"/> would produce for the current moment (optionally
    /// offset by <paramref name="offsetAmount"/>/<paramref name="offsetUnit"/>), without throwing
    /// on invalid or partial input while the user is typing.
    /// </summary>
    public static string SafePreview(string? format, int? offsetAmount = null, DateOffsetUnit? offsetUnit = null, TimeProvider? clock = null)
    {
        if (string.IsNullOrEmpty(format)) return "";

        DateTime moment = (clock ?? TimeProvider.System).GetLocalNow().DateTime;
        if (offsetAmount is { } amount && offsetUnit is { } unit)
        {
            moment = unit switch
            {
                DTOs.DateOffsetUnit.Seconds => moment.AddSeconds(amount),
                DTOs.DateOffsetUnit.Minutes => moment.AddMinutes(amount),
                DTOs.DateOffsetUnit.Hours => moment.AddHours(amount),
                DTOs.DateOffsetUnit.Days => moment.AddDays(amount),
                _ => moment,
            };
        }

        try
        {
            // A single-character custom format specifier (e.g. "d") is ambiguous with .NET's
            // standard format specifiers. Prefixing with '%' forces custom-specifier interpretation.
            string actualFormat = format.Length == 1 ? "%" + format : format;
            return moment.ToString(actualFormat);
        }
        catch (FormatException)
        {
            return "Invalid format";
        }
    }

    private static string FormatUnitName(DateOffsetUnit unit, int amount)
    {
        string name = unit.ToString().ToLowerInvariant();
        return Math.Abs(amount) == 1 ? name[..^1] : name;
    }
}
