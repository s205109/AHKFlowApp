using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class ProfileEditModel
{
    public string Name { get; set; } = "";
    public string HeaderTemplate { get; set; } = "";
    public string FooterTemplate { get; set; } = "";
    public bool IsDefault { get; set; }

    public static ProfileEditModel FromDto(ProfileDto dto) => new()
    {
        Name = dto.Name,
        HeaderTemplate = dto.HeaderTemplate,
        FooterTemplate = dto.FooterTemplate,
        IsDefault = dto.IsDefault,
    };

    public CreateProfileDto ToCreateDto() =>
        new(Name, HeaderTemplate, FooterTemplate, IsDefault);

    public UpdateProfileDto ToUpdateDto() =>
        new(Name, HeaderTemplate, FooterTemplate, IsDefault);
}
