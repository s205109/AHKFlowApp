namespace AHKFlowApp.API.Filters;

/// <summary>
/// Returns 404 for every action on the decorated controller outside the Development
/// environment, failing fast before authentication, model binding, or use-case dispatch.
/// </summary>
public sealed class DevelopmentOnlyAttribute : Attribute
{
}
