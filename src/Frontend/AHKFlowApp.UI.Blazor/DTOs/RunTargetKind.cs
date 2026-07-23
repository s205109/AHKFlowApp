namespace AHKFlowApp.UI.Blazor.DTOs;

/// <summary>Display label for a Run target. Does not change emission. Mirror of the backend enum.</summary>
public enum RunTargetKind
{
    Application = 0,
    Url = 1,
    Folder = 2,
}
