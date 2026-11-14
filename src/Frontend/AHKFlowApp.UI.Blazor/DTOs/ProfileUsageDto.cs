namespace AHKFlowApp.UI.Blazor.DTOs;

public sealed record ProfileUsageDto(
    int HotstringsLeftWithNoProfile,
    int HotkeysLeftWithNoProfile)
{
    public int Total => HotstringsLeftWithNoProfile + HotkeysLeftWithNoProfile;
}
