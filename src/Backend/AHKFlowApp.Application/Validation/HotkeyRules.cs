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

    // Key and Parameters are embedded raw by AhkScriptGenerator.FormatHotkey; the character
    // rejections below keep the generated line valid AHK v2 (same trust model as ContextValue
    // in HotstringRules.AddWindowContextRules). Colon is rejected only in Key: "a:" would emit
    // "a:::...", which AHK parses as hotstring syntax. Interim until escaping lands (see the
    // follow-up to issue #193).
    public static IRuleBuilderOptions<T, string> ValidKey<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .Must(k => !string.IsNullOrEmpty(k)).WithMessage("Key is required.")
          .MaximumLength(KeyMaxLength).WithMessage($"Key must be {KeyMaxLength} characters or fewer.")
          .Must(k => k is not null && !k.Any(char.IsControl))
              .WithMessage("Key must not contain control characters.")
          .Must(k => k is not null && k.Length == k.TrimStart(' ').TrimEnd(' ').Length)
              .WithMessage("Key must not have leading or trailing whitespace.")
          .Must(k => k is not null && !k.Contains('"'))
              .WithMessage("Key must not contain double-quote characters.")
          .Must(k => k is not null && !k.Contains('`'))
              .WithMessage("Key must not contain backtick characters.")
          .Must(k => k is not null && !k.Contains(':'))
              .WithMessage("Key must not contain colon characters.");

    public static IRuleBuilderOptions<T, string> ValidParameters<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .MaximumLength(ParametersMaxLength)
              .WithMessage($"Parameters must be {ParametersMaxLength} characters or fewer.")
          .Must(p => p is null || !p.Contains('"'))
              .WithMessage("Parameters must not contain double-quote characters.")
          .Must(p => p is null || !p.Contains('`'))
              .WithMessage("Parameters must not contain backtick characters.")
          .Must(p => p is null || !p.Any(char.IsControl))
              .WithMessage("Parameters must not contain control characters.");

    public static IRuleBuilderOptions<T, HotkeyAction> ValidAction<T>(this IRuleBuilderInitial<T, HotkeyAction> rb) =>
        rb.IsInEnum().WithMessage("Action must be a valid HotkeyAction value.");
}
