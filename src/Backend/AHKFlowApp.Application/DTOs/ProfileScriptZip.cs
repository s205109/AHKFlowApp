namespace AHKFlowApp.Application.DTOs;

/// <summary>Zip archive with one generated .ahk script per profile.</summary>
/// <param name="Content">Raw bytes of the zip archive.</param>
/// <param name="FileName">Suggested download file name for the archive.</param>
public sealed record ProfileScriptZip(byte[] Content, string FileName);
