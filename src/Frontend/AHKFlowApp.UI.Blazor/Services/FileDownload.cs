namespace AHKFlowApp.UI.Blazor.Services;

public sealed record FileDownload(byte[] Content, string FileName, string ContentType);
