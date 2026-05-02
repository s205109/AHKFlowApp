using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotstringRules
{
    public const int TriggerMaxLength = 50;
    public const int ReplacementMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidTrigger<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(t => !string.IsNullOrEmpty(t)).WithMessage("Trigger is required.")
          .MaximumLength(TriggerMaxLength).WithMessage($"Trigger must be {TriggerMaxLength} characters or fewer.")
          .Must(t => t is not null && t.Length == t.Trim().Length)
              .WithMessage("Trigger must not have leading or trailing whitespace.")
          .Must(t => t is not null && t.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Trigger must not contain line breaks or tabs.");

    public static IRuleBuilderOptions<T, string> ValidReplacement<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Replacement is required.")
          .MaximumLength(ReplacementMaxLength).WithMessage($"Replacement must be {ReplacementMaxLength} characters or fewer.");

    /// <summary>
    /// Adds profile-association validation rules to a validator.
    /// When <paramref name="appliesToAll"/> is true, <paramref name="profileIds"/> must be null/empty.
    /// When false, at least one non-empty GUID must be provided.
    /// Failures key off the <paramref name="profileIds"/> expression so PropertyName matches the DTO path (e.g. "Input.ProfileIds").
    /// </summary>
    public static void AddProfileAssociationRules<T>(
        this AbstractValidator<T> validator,
        System.Linq.Expressions.Expression<Func<T, bool>> appliesToAll,
        System.Linq.Expressions.Expression<Func<T, Guid[]?>> profileIds)
    {
        Func<T, bool> appliesToAllFn = appliesToAll.Compile();

        // When AppliesToAllProfiles = true, ProfileIds must be empty
        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.Length == 0)
            .When(x => appliesToAllFn(x))
            .WithMessage("ProfileIds must be empty when AppliesToAllProfiles is true.");

        // When AppliesToAllProfiles = false, at least one profile required
        validator.RuleFor(profileIds)
            .Must(ids => ids is { Length: > 0 })
            .When(x => !appliesToAllFn(x))
            .WithMessage("At least one profile must be specified when AppliesToAllProfiles is false.");

        // No empty GUIDs in the array
        validator.RuleFor(profileIds)
            .Must(ids => ids is null || ids.All(id => id != Guid.Empty))
            .When(x => !appliesToAllFn(x))
            .WithMessage("ProfileIds must not contain empty GUIDs.");
    }
}
