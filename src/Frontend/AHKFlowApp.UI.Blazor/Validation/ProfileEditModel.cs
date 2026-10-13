using AHKFlowApp.UI.Blazor.Constants;
using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class ProfileEditModel
{
    public string Name { get; set; } = "";
    public string HeaderTemplate { get; set; } = "";
    public string FooterTemplate { get; set; } = "";
    public bool IsDefault { get; set; }

    /// <summary>
    /// The model behind the Add row. It starts from the default templates, so the owner sees the
    /// header they are about to get, and can edit or clear it. Before this existed the Add row
    /// sent an empty header. The server falls back to the default only when the header is null,
    /// so every profile made in the web UI stored no directives at all.
    /// </summary>
    public static ProfileEditModel ForNewProfile() => new()
    {
        HeaderTemplate = DefaultProfileTemplates.Header,
        FooterTemplate = DefaultProfileTemplates.Footer,
    };

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
