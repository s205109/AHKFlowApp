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
            .WithMessage("Match by and Value under Window context must both be set, or both be empty.");

        validator.RuleFor(contextMatchType)
            .IsInEnum()
            .WithMessage("Choose an option in Match by under Window context.");

        validator.RuleFor(contextValue)
            .Must(v => v is null || !string.IsNullOrWhiteSpace(v))
                .WithMessage("Value under Window context must not be blank.")
            .MaximumLength(ContextValueMaxLength)
                .WithMessage($"Value under Window context must be {ContextValueMaxLength} characters or fewer.")
            .Must(v => v is null || !v.Contains('"'))
                .WithMessage("Value under Window context must not contain double quotes.")
            .Must(v => v is null || !v.Contains('`'))
                .WithMessage("Value under Window context must not contain backticks.")
            .Must(v => v is null || !v.Any(char.IsControl))
                .WithMessage("Value under Window context must not contain control characters.");
    }
}
