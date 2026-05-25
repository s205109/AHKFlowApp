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
    };

    public CreateHotstringDto ToCreateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord, Description, [.. CategoryIds]);

    public UpdateHotstringDto ToUpdateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord, Description, [.. CategoryIds]);
}
