using Microsoft.JSInterop;

namespace AHKFlowApp.UI.Blazor.Services;

public sealed class JsFileSaver(IJSRuntime js) : IFileSaver
{
    public async Task SaveAsync(string fileName, string contentType, byte[] content)
    {
        string base64 = Convert.ToBase64String(content);
        await js.InvokeVoidAsync("ahkFlowDownloads.saveBlob", fileName, contentType, base64);
    }
}
