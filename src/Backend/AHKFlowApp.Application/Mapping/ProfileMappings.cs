using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class ProfileMappings
{
    public static ProfileDto ToDto(this Profile p) => new(
        p.Id,
        p.Name,
        p.IsDefault,
        p.HeaderTemplate,
        p.FooterTemplate,
        p.CreatedAt,
        p.UpdatedAt);
}
