namespace AHKFlowApp.Application.Commands.Hotstrings;

/// <summary>
/// Shared duplicate-trigger conflict message for hotstring create, update, restore, and revert
/// handlers. The composite unique index allows the same trigger to exist once globally and once
/// per distinct window context, so the message calls out "in the same context" explicitly.
/// </summary>
internal static class HotstringConflictMessages
{
    public const string DuplicateTrigger = "A hotstring with this trigger already exists in the same context.";
}
