using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class HotkeyRules
{
    public const int TriggerMaxLength = 100;
    public const int ActionMaxLength = 4000;
    public const int DescriptionMaxLength = 200;

    public static IRuleBuilderOptions<T, string> ValidHotkeyTrigger<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(t => !string.IsNullOrEmpty(t)).WithMessage("Trigger is required.")
          .MaximumLength(TriggerMaxLength).WithMessage($"Trigger must be {TriggerMaxLength} characters or fewer.")
          .Must(t => t is not null && t.Length == t.Trim().Length)
              .WithMessage("Trigger must not have leading or trailing whitespace.")
          .Must(t => t is not null && t.IndexOfAny(['\n', '\r', '\t']) < 0)
              .WithMessage("Trigger must not contain line breaks or tabs.");

    public static IRuleBuilderOptions<T, string> ValidAction<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Action is required.")
          .MaximumLength(ActionMaxLength).WithMessage($"Action must be {ActionMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, string?> ValidOptionalDescription<T>(this IRuleBuilder<T, string?> rb) =>
        rb.MaximumLength(DescriptionMaxLength).WithMessage($"Description must be {DescriptionMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, Guid?> ValidOptionalProfileId<T>(this IRuleBuilder<T, Guid?> rb) =>
        rb.Must(id => id is null || id != Guid.Empty)
          .WithMessage("ProfileId must not be an empty GUID.");
}
