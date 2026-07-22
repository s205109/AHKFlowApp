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

    // Double-quote and backtick are no longer rejected: HotkeyEmitter escapes Parameters
    // into the emitted string literal, so they are ordinary characters now. Control
    // characters stay rejected — the escape routine only covers \n, \r and \t, and the
    // rest have no meaningful representation in a single-line definition.
    public static IRuleBuilderOptions<T, string> ValidParameters<T>(this IRuleBuilderInitial<T, string> rb) =>
        rb.Cascade(CascadeMode.Stop)
          .MaximumLength(ParametersMaxLength)
              .WithMessage($"Parameters must be {ParametersMaxLength} characters or fewer.")
          .Must(p => p is null || !p.Any(c => char.IsControl(c) && c is not '\n' and not '\r' and not '\t'))
              .WithMessage("Parameters must not contain control characters.");

    public static IRuleBuilderOptions<T, HotkeyAction> ValidAction<T>(this IRuleBuilderInitial<T, HotkeyAction> rb) =>
        rb.IsInEnum().WithMessage("Action must be a valid HotkeyAction value.");

    /// <summary>
    /// Pure token grammars for the two validated-token action kinds (spec §8). Public so validators
    /// and unit tests share exactly one implementation of each rule.
    /// </summary>
    public static class Tokens
    {
        /// <summary>
        /// A <c>SendKeys</c> token: optional <c>^ ! + #</c> modifiers (each at most once, any order;
        /// <c>*</c> is NOT a Send modifier) then exactly one key — a single printable character bare
        /// (<c>c</c>), or a registry key with the <c>SendToken</c> role braced (<c>{Volume_Up}</c>).
        /// A named key unbraced, a double-brace macro leak, and multiple keys are all rejected.
        /// </summary>
        public static bool IsValidSendKeysContent(string? content)
        {
            if (string.IsNullOrEmpty(content))
                return false;

            int i = 0;
            var seen = new HashSet<char>();
            while (i < content.Length && content[i] is '^' or '!' or '+' or '#')
            {
                if (!seen.Add(content[i]))
                    return false; // duplicate modifier
                i++;
            }

            string key = content[i..];
            if (key.Length == 0)
                return false; // modifiers but no key

            if (key[0] == '{')
            {
                if (key.Length < 3 || key[^1] != '}')
                    return false;
                string inner = key[1..^1];
                // Exactly one braced token: no nested/second brace (rejects {{date...}} and {a}{b}).
                if (inner.Length == 0 || inner.Contains('{') || inner.Contains('}'))
                    return false;

                if (!HotkeyKeys.TryCanonicalize(inner, out string canonical))
                    return false;
                // vk/sc codes are valid Send tokens; named keys must carry the SendToken role.
                return !HotkeyKeys.IsRegistryName(canonical)
                    || HotkeyKeys.HotkeyKeyEntryByCanonical(canonical).Roles.HasFlag(HotkeyKeyRoles.SendToken);
            }

            // Bare: exactly one printable, non-brace, non-modifier character. Quote and backtick
            // stay valid here — Send can type them. They are hostile to the *string literal*, not
            // to Send, so the emitter escapes them (Task 5); this validator owns Send semantics only.
            return key.Length == 1 && !char.IsControl(key[0]) && key[0] is not '{' and not '}';
        }

        /// <summary>
        /// A <c>RemapDest</c> token: a single registry key with the <c>RemapDest</c> role, or a
        /// <c>vk</c>/<c>sc</c> code. No modifiers, no braces (spec §8).
        /// </summary>
        public static bool IsValidRemapDest(string? dest) => HotkeyKeys.IsValidRemapDest(dest);
    }
}
