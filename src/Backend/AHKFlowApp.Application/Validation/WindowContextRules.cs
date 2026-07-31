using System.Linq;
using System.Linq.Expressions;
using AHKFlowApp.Domain.Enums;
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

/// <summary>
/// Validation for the optional window context a hotstring or a hotkey can carry. Both entities use
/// the same pair of fields and the same generated <c>WinActive(...)</c> expression, so the rules
/// live here rather than in <see cref="HotstringRules"/>.
/// </summary>
internal static class WindowContextRules
{
    public const int ContextValueMaxLength = 200;

    /// <summary>
    /// Adds validation for an optional window-context match, independent of hotstring kind or
    /// hotkey action kind: <paramref name="contextMatchType"/> and <paramref name="contextValue"/>
    /// must both be null or both be set, the match type must be a valid
    /// <see cref="WindowMatchType"/>, and the value must not be blank/whitespace-only, is capped at
    /// <see cref="ContextValueMaxLength"/> characters, and must not contain a double-quote,
    /// backtick, or any control character &#8212; it is embedded raw into a generated
    /// <c>WinActive(...)</c> AHK expression, so these characters would break or escape that syntax.
    /// </summary>
    public static void AddWindowContextRules<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, WindowMatchType?>> contextMatchType,
        Expression<Func<T, string?>> contextValue)
    {
        Func<T, string?> valueFn = contextValue.Compile();

        // Both-or-neither
        validator.RuleFor(contextMatchType)
            .Must((x, matchType) => (matchType is null) == (valueFn(x) is null))
            .WithMessage("ContextMatchType and ContextValue must both be set or both be null.");

        validator.RuleFor(contextMatchType)
            .IsInEnum();

        validator.RuleFor(contextValue)
            .Must(v => v is null || !string.IsNullOrWhiteSpace(v))
                .WithMessage("ContextValue must not be blank or whitespace.")
            .MaximumLength(ContextValueMaxLength)
                .WithMessage($"ContextValue must be {ContextValueMaxLength} characters or fewer.")
            .Must(v => v is null || !v.Contains('"'))
                .WithMessage("ContextValue must not contain double-quote characters.")
            .Must(v => v is null || !v.Contains('`'))
                .WithMessage("ContextValue must not contain backtick characters.")
            .Must(v => v is null || !v.Any(char.IsControl))
                .WithMessage("ContextValue must not contain control characters.");
    }
}
