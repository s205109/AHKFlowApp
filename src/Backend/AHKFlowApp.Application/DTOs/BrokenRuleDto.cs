namespace AHKFlowApp.Application.DTOs;

/// <summary>One rule that a stored hotstring or hotkey breaks.</summary>
/// <param name="Field">The property the rule belongs to, such as <c>ContextValue</c>.</param>
/// <param name="Message">The rule's message, as a save would report it.</param>
public sealed record BrokenRuleDto(string Field, string Message);
