using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class CategoryMapping
{
    public static CategoryDto ToDto(this Category c) => new(c.Id, c.Name, c.CreatedAt, c.UpdatedAt);
}
