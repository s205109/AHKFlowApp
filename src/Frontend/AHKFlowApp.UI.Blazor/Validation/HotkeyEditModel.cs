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
    public List<Guid> CategoryIds { get; set; } = [];

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
        CategoryIds = [.. dto.CategoryIds ?? []],
    };

    public HotkeyEditModel Clone() => new()
    {
        Id = Id,
        Description = Description,
        Key = Key,
        Ctrl = Ctrl,
        Alt = Alt,
        Shift = Shift,
        Win = Win,
        Action = Action,
        Parameters = Parameters,
        AppliesToAllProfiles = AppliesToAllProfiles,
        ProfileIds = [.. ProfileIds],
        CategoryIds = [.. CategoryIds],
    };

    public CreateHotkeyDto ToCreateDto() =>
        new(Description, Key, ToActionKind(Action), Ctrl, Alt, Shift, Win,
            ProfileIds: AppliesToAllProfiles ? null : [.. ProfileIds],
            AppliesToAllProfiles: AppliesToAllProfiles,
            CategoryIds: [.. CategoryIds],
            Action: Action,
            Parameters: Parameters);

    public UpdateHotkeyDto ToUpdateDto() =>
        new(Description, Key, ToActionKind(Action), Ctrl, Alt, Shift, Win,
            Text: null, SendKeysContent: null, RunTarget: null, RunTargetKind: null, WindowOp: null,
            RemapDest: null, Body: null,
            ProfileIds: AppliesToAllProfiles ? null : [.. ProfileIds],
            AppliesToAllProfiles: AppliesToAllProfiles,
            CategoryIds: [.. CategoryIds],
            Action: Action,
            Parameters: Parameters);

    // Bridges the legacy two-value Action to the typed ActionKind the DTOs now require. This is
    // a compile-time placeholder, not the real conversion — Task 5 retypes this model with its
    // own ActionKind field and per-kind panels, at which point this mapping is removed entirely.
    private static HotkeyActionKind ToActionKind(HotkeyAction action) => action switch
    {
        HotkeyAction.Run => HotkeyActionKind.Run,
        _ => HotkeyActionKind.SendKeys,
    };
}
