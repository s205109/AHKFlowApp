using System.ComponentModel.DataAnnotations;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class HotkeyEditModel
{
    public Guid? Id { get; set; }

    [Required(ErrorMessage = "Description is required.")]
    [MaxLength(200, ErrorMessage = "Description must be 200 characters or fewer.")]
    public string Description { get; set; } = "";

    [Required(ErrorMessage = "Key is required.")]
    [MaxLength(20, ErrorMessage = "Key must be 20 characters or fewer.")]
    public string Key { get; set; } = "";

    public bool Ctrl { get; set; }
    public bool Alt { get; set; }
    public bool Shift { get; set; }
    public bool Win { get; set; }
    public HotkeyAction Action { get; set; } = HotkeyAction.Send;

    [MaxLength(4000, ErrorMessage = "Parameters must be 4000 characters or fewer.")]
    public string Parameters { get; set; } = "";

    public bool AppliesToAllProfiles { get; set; } = true;
    public List<Guid> ProfileIds { get; set; } = [];

    public static HotkeyEditModel FromDto(HotkeyDto dto) => new()
    {
        Id = dto.Id,
        Description = dto.Description,
        Key = dto.Key,
        Ctrl = dto.Ctrl,
        Alt = dto.Alt,
        Shift = dto.Shift,
        Win = dto.Win,
        Action = dto.Action,
        Parameters = dto.Parameters,
        AppliesToAllProfiles = dto.AppliesToAllProfiles,
        ProfileIds = [.. dto.ProfileIds],
    };

    public CreateHotkeyDto ToCreateDto() =>
        new(Description, Key, Ctrl, Alt, Shift, Win, Action, Parameters,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles);

    public UpdateHotkeyDto ToUpdateDto() =>
        new(Description, Key, Ctrl, Alt, Shift, Win, Action, Parameters,
            AppliesToAllProfiles ? null : [.. ProfileIds], AppliesToAllProfiles);
}
