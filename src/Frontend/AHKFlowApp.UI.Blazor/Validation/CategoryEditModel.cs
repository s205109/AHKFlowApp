using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Validation;

public sealed class CategoryEditModel
{
    public string Name { get; set; } = "";

    public static CategoryEditModel FromDto(CategoryDto dto) => new() { Name = dto.Name };

    public CreateCategoryDto ToCreateDto() => new(Name);

    public UpdateCategoryDto ToUpdateDto() => new(Name);
}
