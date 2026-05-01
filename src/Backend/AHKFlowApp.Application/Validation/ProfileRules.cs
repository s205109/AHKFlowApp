using FluentValidation;

namespace AHKFlowApp.Application.Validation;

internal static class ProfileRules
{
    public const int NameMaxLength = 100;
    public const int HeaderTemplateMaxLength = 8000;
    public const int FooterTemplateMaxLength = 4000;

    public static IRuleBuilderOptions<T, string> ValidName<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Name is required.")
          .MaximumLength(NameMaxLength).WithMessage($"Name must be {NameMaxLength} characters or fewer.")
          .Must(n => n is not null && n.Length == n.Trim().Length)
              .WithMessage("Name must not have leading or trailing whitespace.");

    public static IRuleBuilderOptions<T, string?> ValidHeaderTemplate<T>(this IRuleBuilderInitial<T, string?> rb) =>
        rb.MaximumLength(HeaderTemplateMaxLength)
          .WithMessage($"HeaderTemplate must be {HeaderTemplateMaxLength} characters or fewer.");

    public static IRuleBuilderOptions<T, string?> ValidFooterTemplate<T>(this IRuleBuilderInitial<T, string?> rb) =>
        rb.MaximumLength(FooterTemplateMaxLength)
          .WithMessage($"FooterTemplate must be {FooterTemplateMaxLength} characters or fewer.");
}
