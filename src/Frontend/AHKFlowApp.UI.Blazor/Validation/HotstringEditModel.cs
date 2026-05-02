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

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];
    public bool IsEndingCharacterRequired { get; set; } = true;
    public bool IsTriggerInsideWord { get; set; } = true;

    public static HotstringEditModel FromDto(HotstringDto dto) => new()
    {
        Id = dto.Id,
        Trigger = dto.Trigger,
        Replacement = dto.Replacement,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
        IsEndingCharacterRequired = dto.IsEndingCharacterRequired,
        IsTriggerInsideWord = dto.IsTriggerInsideWord,
    };

    public CreateHotstringDto ToCreateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord);

    public UpdateHotstringDto ToUpdateDto() =>
        new(Trigger, Replacement, AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles, IsEndingCharacterRequired, IsTriggerInsideWord);
}
