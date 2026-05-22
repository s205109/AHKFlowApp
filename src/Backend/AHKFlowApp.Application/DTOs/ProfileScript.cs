namespace AHKFlowApp.Application.DTOs;

/// <summary>A rendered AutoHotkey script for a profile.</summary>
/// <param name="FileName">Suggested filename for download, such as <c>Work.ahk</c>.</param>
/// <param name="Content">Full script body.</param>
public sealed record ProfileScript(string FileName, string Content);
