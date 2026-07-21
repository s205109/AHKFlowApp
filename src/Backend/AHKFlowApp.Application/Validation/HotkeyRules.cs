using AHKFlowApp.Application.Constants;
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

    // Key is validated against the canonical registry (or a vkNN / scNNN code) rather than
    // by rejecting known-bad characters. This is the whitelist half of issue #195: an
    // accepted Key is a real AHK key name, so the emitted left-hand side cannot break the
    // script. Escaping of the right-hand side lives in HotkeyEmitter.
    public static IRuleBuilderOptions<T, string> ValidKey<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .NotEmpty().WithMessage("Key is required.")
          .MaximumLength(KeyMaxLength).WithMessage($"Key must be {KeyMaxLength} characters or fewer.")
          .Must(HotkeyKeys.IsValidHotkeyKey)
              .WithMessage("Key must be a known key name (for example a, F5, Escape, Numpad0) "
                         + "or a vkNN / scNNN code. Combined vkNNscNNN is not valid in a hotkey.");

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
