namespace AHKFlowApp.UI.Blazor.Components.Common;

/// <summary>
/// Lightweight id/name projection used by the shared entity selection and chip components,
/// so they don't need to know about concrete DTO types.
/// </summary>
public sealed record EntityOption(Guid Id, string Name);
