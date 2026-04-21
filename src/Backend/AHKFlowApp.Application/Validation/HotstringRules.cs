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

    public static IRuleBuilderOptions<T, Guid?> ValidOptionalProfileId<T>(this IRuleBuilder<T, Guid?> rb) =>
        rb.Must(id => id is null || id != Guid.Empty)
          .WithMessage("ProfileId must not be an empty GUID.");
}
