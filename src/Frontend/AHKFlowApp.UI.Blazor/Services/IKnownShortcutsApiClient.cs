using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Services;

/// <summary>Reads the list of shortcuts something outside AHKFlow already uses, and edits the owner's part of it.</summary>
public interface IKnownShortcutsApiClient
{
    /// <summary>Every known shortcut the dialog may warn about. Ignored uses are left out.</summary>
    Task<ApiResult<KnownShortcutCatalogDto>> ListAsync(CancellationToken ct = default);

    /// <summary>Every known shortcut for the management page, ignored uses included.</summary>
    Task<ApiResult<ManagedKnownShortcutCatalogDto>> ListManagedAsync(CancellationToken ct = default);

    /// <summary>Records something the owner knows uses a combination. Returns the whole merged list.</summary>
    Task<ApiResult<ManagedKnownShortcutCatalogDto>> CreateAsync(
        CreateCustomKnownShortcutDto input, CancellationToken ct = default);

    /// <summary>Removes one of the owner's own records.</summary>
    Task<ApiResult> DeleteAsync(Guid id, CancellationToken ct = default);

    /// <summary>Stops warning about one built-in use. Other uses of the same keys still warn.</summary>
    Task<ApiResult> IgnoreAsync(string shortcutId, string usedBy, CancellationToken ct = default);

    /// <summary>Warns about a built-in use again.</summary>
    Task<ApiResult> RestoreAsync(string shortcutId, string usedBy, CancellationToken ct = default);
}
