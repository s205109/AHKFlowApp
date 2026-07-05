namespace AHKFlowApp.Application.DTOs;

/// <summary>Zip archive with one generated .ahk script per profile.</summary>
public sealed record ProfileScriptZip(byte[] Content, string FileName);
