using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotstringEditModel
{
    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Trigger is required.")]
    [MaxLength(50, ErrorMessage = "Trigger must be 50 characters or fewer.")]
    public string Trigger { get; set; } = "";

    [Required(ErrorMessage = "Replacement is required.")]
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

    /// <summary>UI-facing inverse of <see cref="IsEndingCharacterRequired"/> (spec label "Expand immediately").</summary>
    public bool ExpandImmediately
    {
        get => !IsEndingCharacterRequired;
        set => IsEndingCharacterRequired = !value;
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
    };

    public CreateHotstringDto ToCreateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord, Description, [.. CategoryIds], Kind, IsCaseSensitive, OmitEndingCharacter);

    public UpdateHotstringDto ToUpdateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord, Description, [.. CategoryIds], Kind, IsCaseSensitive, OmitEndingCharacter);
}
