using System.Linq.Expressions;
using AHKFlowApp.Domain.Enums;
using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotkeyRules
{
    public const int DescriptionMaxLength = 200;
    public const int KeyMaxLength = 20;
    public const int ParametersMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidDescription<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Description is required.")
          .MaximumLength(DescriptionMaxLength).WithMessage($"Description must be {DescriptionMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, string> ValidKey<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(k => !string.IsNullOrEmpty(k)).WithMessage("Key is required.")
          .MaximumLength(KeyMaxLength).WithMessage($"Key must be {KeyMaxLength} characters or fewer.")
          .Must(k => k is not null && k.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Key must not contain line breaks or tabs.")
          .Must(k => k is not null && k.Length == k.TrimStart(' ').TrimEnd(' ').Length)
              .WithMessage("Key must not have leading or trailing whitespace.");

    public static IRuleBuilderOptions<T, string> ValidParameters<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.MaximumLength(ParametersMaxLength)
          .WithMessage($"Parameters must be {ParametersMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, HotkeyAction> ValidAction<T>(this IRuleBuilderInitial<T, HotkeyAction> rb) =>
        rb.IsInEnum().WithMessage("Action must be a valid HotkeyAction value.");

    public static void ValidProfileAssociation<T>(
        this AbstractValidator<T> validator,
        Expression<Func<T, bool>> appliesToAll,
        Expression<Func<T, Guid[]?>> profileIds)
    {
        Func<T, bool> appliesToAllFn = appliesToAll.Compile();

        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.Length == 0)
            .When(x => appliesToAllFn(x))
            .WithMessage("ProfileIds must be empty when AppliesToAllProfiles is true.");

        validator.RuleFor(profileIds)
            .Must(ids => ids is { Length: > 0 })
            .When(x => !appliesToAllFn(x))
            .WithMessage("At least one profile must be specified when AppliesToAllProfiles is false.");

        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.All(id => id != Guid.Empty))
            .When(x => !appliesToAllFn(x))
            .WithMessage("ProfileIds must not contain empty GUIDs.");
    }
}
