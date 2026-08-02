using AHKFlowApp.UI.Blazor.DTOs;

namespace AHKFlowApp.UI.Blazor.Components.KnownShortcuts;

/// <summary>
/// One use, flattened out of its combination so a list stays one row per item. A browser
/// combination holds a Chrome use and an Edge use, and each is silenced on its own, so the
/// combination label repeats across rows.
/// </summary>
public sealed record KnownShortcutUseRow(string ShortcutId, string ComboLabel, ManagedShortcutUseDto Use);
