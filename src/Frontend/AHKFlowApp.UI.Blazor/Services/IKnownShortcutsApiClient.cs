using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>Reads the curated list of shortcuts something outside AHKFlow already uses.</summary>
public interface IKnownShortcutsApiClient
{
    /// <summary>Every known shortcut the dialog may warn about.</summary>
    Task<ApiResult<KnownShortcutCatalogDto>> ListAsync(CancellationToken ct = default);
}
