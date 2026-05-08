namespace AHKFlowApp.UI.Blazor.Services;

public interface IFileSaver
{
    Task SaveAsync(string fileName, string contentType, byte[] content);
}
