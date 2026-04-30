using AHKFlowApp.Application.DTOs;
using AHKFlowApp.Domain.Entities;

namespace AHKFlowApp.Application.Mapping;

internal static class UserPreferenceMappings
{
    public static UserPreferenceDto ToDto(this UserPreference p) => new(p.RowsPerPage, p.DarkMode);
}
